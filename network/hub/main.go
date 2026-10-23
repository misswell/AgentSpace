package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/misswell/AgentSpace/network/hub/internal/store"
)

// The hub's control plane.
//
// It answers three questions and refuses everything else:
//   - a new node can enroll with a one-time token and learn its fixed address;
//   - an enrolled node can fetch the peer list it must configure;
//   - an operator can create tokens and revoke nodes, locally only.
//
// It deliberately does not proxy traffic, does not run commands, and has no
// endpoint that accepts a shell, a path or a firewall rule. The WireGuard
// interface carries packets; this process only decides who is in the network.

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	command := os.Args[1]
	defaultState := envOr("AGENTSPACE_HUB_STATE", "/var/lib/agentspace-hub/hub.json")

	switch command {
	case "init":
		fs := flag.NewFlagSet("init", flag.ExitOnError)
		statePath := fs.String("state", defaultState, "state file")
		pool := fs.String("pool", "", "virtual IPv4 pool, e.g. 100.64.7.0/24")
		port := fs.Int("listen-port", 51820, "WireGuard UDP port")
		_ = fs.Parse(os.Args[2:])
		if *pool == "" {
			fmt.Fprintln(os.Stderr, "init requires --pool CIDR")
			os.Exit(2)
		}
		state, err := store.Init(*statePath, *pool, *port)
		if err != nil {
			fmt.Fprintln(os.Stderr, "init:", err)
			os.Exit(1)
		}
		fmt.Printf("network %s\n  pool:   %s\n  hub:    %s\n  state:  %s\n",
			state.NetworkID, state.Pool, state.HubAddr, *statePath)

	case "enroll-token":
		fs := flag.NewFlagSet("enroll-token", flag.ExitOnError)
		statePath := fs.String("state", defaultState, "state file")
		label := fs.String("label", "", "what this token is for")
		role := fs.String("role", string(store.RoleNode), "node role: agentspace|controller|node")
		_ = fs.Parse(os.Args[2:])
		token, secret, err := store.CreateEnrollment(*statePath, *label, store.Role(*role))
		if err != nil {
			fmt.Fprintln(os.Stderr, "enroll-token:", err)
			os.Exit(1)
		}
		fmt.Printf("enrollment %s (%s)\n  token: %s\n  This is the only time it is shown.\n",
			token.ID, token.Label, secret)

	case "serve":
		fs := flag.NewFlagSet("serve", flag.ExitOnError)
		statePath := fs.String("state", defaultState, "state file")
		listen := fs.String("listen", "127.0.0.1:8788", "control-plane listen address (never 0.0.0.0)")
		_ = fs.Parse(os.Args[2:])
		if strings.HasPrefix(*listen, "0.0.0.0") || strings.HasPrefix(*listen, "[::]") {
			// The control plane hands out addresses and keys. Exposing it on every
			// interface turns a laptop on a café network into a network controller
			// for whoever can reach it.
			fmt.Fprintln(os.Stderr, "refusing to listen on all interfaces; the control plane binds to one address (put a reverse proxy in front if it must be reachable)")
			os.Exit(1)
		}
		serve(*statePath, *listen)

	case "list":
		fs := flag.NewFlagSet("list", flag.ExitOnError)
		statePath := fs.String("state", defaultState, "state file")
		_ = fs.Parse(os.Args[2:])
		st, err := store.New(*statePath)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		state, err := st.Load()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		now := time.Now()
		fmt.Printf("network %s  pool %s  hub %s  version %d\n", state.NetworkID, state.Pool, state.HubAddr, state.Version)
		for _, node := range state.Active() {
			status := "offline"
			if node.Online(now) {
				status = "online"
			}
			fmt.Printf("  %-15s %-11s %-16s %s\n", node.Address, node.Role, node.Name, status)
		}

	case "revoke":
		fs := flag.NewFlagSet("revoke", flag.ExitOnError)
		statePath := fs.String("state", defaultState, "state file")
		_ = fs.Parse(os.Args[2:])
		if fs.NArg() < 1 {
			fmt.Fprintln(os.Stderr, "revoke requires a node id or name")
			os.Exit(2)
		}
		if _, err := store.Revoke(*statePath, fs.Arg(0)); err != nil {
			fmt.Fprintln(os.Stderr, "revoke:", err)
			os.Exit(1)
		}
		fmt.Println("revoked", fs.Arg(0))

	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `agentspace-hub — control plane for an AgentSpace virtual network

  agentspace-hub init --pool CIDR [--listen-port 51820] [--state PATH]
  agentspace-hub enroll-token --label NAME [--role node|controller|agentspace]
  agentspace-hub serve [--listen 127.0.0.1:8788] [--state PATH]
  agentspace-hub list [--state PATH]
  agentspace-hub revoke NODE

The hub decides who is in the network and which address each node owns. It does
not carry traffic itself: the WireGuard interface does, configured from the peer
list this process serves.`)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// newMux builds the control-plane routes. Kept separate from serve so the tests
// drive exactly the handler set the binary serves.
func newMux(statePath string) *http.ServeMux {
	mux := http.NewServeMux()

	// Enroll: the only unauthenticated write, and it requires a one-time token.
	mux.HandleFunc("POST /v1/enroll", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Token     string `json:"token"`
			Name      string `json:"name"`
			PublicKey string `json:"publicKey"`
			Endpoint  string `json:"endpoint"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&body); err != nil {
			writeError(w, 400, "BAD_REQUEST", err.Error())
			return
		}
		if body.Token == "" || body.Name == "" || body.PublicKey == "" {
			writeError(w, 400, "BAD_REQUEST", "token, name and publicKey are required")
			return
		}
		state, node, err := store.Enroll(statePath, body.Token, body.Name, body.PublicKey)
		if err != nil {
			writeError(w, 403, "ENROLLMENT_REFUSED", err.Error())
			return
		}
		if body.Endpoint != "" {
			if updated, err := store.UpdateEndpoint(statePath, node.ID, body.Endpoint); err == nil {
				state = updated
			}
		}
		writeJSON(w, 200, map[string]any{
			"ok":      true,
			"node":    node,
			"network": networkView(state),
		})
	})

	// Peers: what a node configures. Authenticated by its own public key, which
	// only it and the hub hold — no shared password exists to leak.
	mux.HandleFunc("GET /v1/network", func(w http.ResponseWriter, r *http.Request) {
		publicKey := r.URL.Query().Get("publicKey")
		if publicKey == "" {
			writeError(w, 401, "UNAUTHORIZED", "publicKey is required")
			return
		}
		st, err := store.New(statePath)
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", err.Error())
			return
		}
		state, err := st.Load()
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", err.Error())
			return
		}
		known := false
		for _, node := range state.Active() {
			if node.PublicKey != "" && node.PublicKey == publicKey {
				known = true
				_, _ = store.Touch(statePath, node.ID)
				break
			}
		}
		if !known {
			writeError(w, 403, "UNAUTHORIZED", "this key is not enrolled in the network")
			return
		}
		writeJSON(w, 200, map[string]any{"ok": true, "network": networkView(state)})
	})

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		st, err := store.New(statePath)
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", err.Error())
			return
		}
		state, err := st.Load()
		if err != nil {
			writeError(w, 500, "INTERNAL_ERROR", err.Error())
			return
		}
		writeJSON(w, 200, map[string]any{
			"ok":      true,
			"network": state.NetworkID,
			"nodes":   len(state.Active()),
			"version": state.Version,
		})
	})

	return mux
}

func serve(statePath, listen string) {
	mux := newMux(statePath)
	server := &http.Server{
		Addr:              listen,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
	}
	listener, err := net.Listen("tcp", listen)
	if err != nil {
		fmt.Fprintln(os.Stderr, "listen:", err)
		os.Exit(1)
	}
	fmt.Printf("hub control plane on http://%s (network %s)\n", listen, mustNetworkID(statePath))
	if err := server.Serve(listener); err != nil {
		fmt.Fprintln(os.Stderr, "serve:", err)
		os.Exit(1)
	}
}

func mustNetworkID(path string) string {
	st, err := store.New(path)
	if err != nil {
		return "?"
	}
	state, err := st.Load()
	if err != nil {
		return "?"
	}
	return state.NetworkID
}

// networkView is what a node receives: every active peer with its exact /32.
// The hub's own public key is included so a node can configure the tunnel to it.
func networkView(state store.State) map[string]any {
	nodes := make([]map[string]any, 0, len(state.Nodes))
	for _, node := range state.Active() {
		nodes = append(nodes, map[string]any{
			"id":         node.ID,
			"name":       node.Name,
			"role":       node.Role,
			"address":    node.Address,
			"publicKey":  node.PublicKey,
			"endpoint":   node.Endpoint,
			"allowedIPs": node.AllowedIPs,
			"online":     node.Online(time.Now()),
		})
	}
	return map[string]any{
		"id":         state.NetworkID,
		"pool":       state.Pool,
		"hubAddress": state.HubAddr,
		"listenPort": state.ListenPort,
		"version":    state.Version,
		"nodes":      nodes,
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{
		"ok": false,
		"error": map[string]any{
			"code":      code,
			"message":   message,
			"recoverable": status >= 500,
		},
	})
}
