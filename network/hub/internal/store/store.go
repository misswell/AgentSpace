package store

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// The hub's state: the network, its nodes, and the enrollment tokens that let a
// new node ask for an address.
//
// One JSON file, replaced atomically. SQLite would be more capable and is
// deliberately not used: the hub's whole state is a few kilobytes, it has one
// writer, and a file a person can read is worth more here than a query planner.
// The atomic replace is what matters — a half-written state file would lose
// every node's address assignment.

type Role string

const (
	RoleHub        Role = "hub"
	RoleController Role = "controller"
	RoleAgentSpace Role = "agentspace"
	RoleNode       Role = "node"
)

// Node is one enrolled device.
type Node struct {
	ID       string    `json:"id"`
	Name     string    `json:"name"`
	Role     Role      `json:"role"`
	Address  string    `json:"address"`
	// PublicKey is the node's WireGuard public key, hex, as WireGuard spells it.
	PublicKey string   `json:"publicKey"`
	Endpoint  string   `json:"endpoint,omitempty"`
	LastSeen  time.Time `json:"lastSeen,omitempty"`
	Revoked   bool     `json:"revoked,omitempty"`
	// AllowedIPs is what the hub routes to this node: that node's own address as
	// a /32, never the pool.
	AllowedIPs []string `json:"allowedIPs"`
}

// EnrollmentToken is a one-time credential a person creates before adding a
// device. The secret is stored only as a digest, exactly like an API token.
type EnrollmentToken struct {
	ID        string    `json:"id"`
	Digest    string    `json:"digest"`
	Label     string    `json:"label"`
	Role      Role      `json:"role"`
	CreatedAt time.Time `json:"createdAt"`
	UsedAt    time.Time `json:"usedAt,omitempty"`
	Revoked   bool      `json:"revoked,omitempty"`
}

type State struct {
	// NetworkID is generated once and never changes, so a node that was enrolled
	// before a restart is still in the same network.
	NetworkID string   `json:"networkId"`
	Pool      string   `json:"pool"`
	HubAddr   string   `json:"hubAddress"`
	// ListenPort is the hub's WireGuard UDP port.
	ListenPort int      `json:"listenPort"`
	Nodes      []Node   `json:"nodes"`
	Enrollments []EnrollmentToken `json:"enrollments"`
	// Version increments on every mutation, so a client can tell a stale
	// configuration from a current one without comparing every field.
	Version   int      `json:"version"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type Store struct {
	mu   sync.Mutex
	path string
}

func New(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return nil, err
	}
	s := &Store{path: path}
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) {
		// Refuse to invent a network: a hub whose pool was chosen by accident
		// would hand out addresses nobody planned for.
		return nil, fmt.Errorf("no hub state at %s — run `net-hub init --pool CIDR` first", path)
	}
	return s, nil
}

// Load reads the state. Callers hold no lock; the store does.
func (s *Store) Load() (State, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.loadLocked()
}

func (s *Store) loadLocked() (State, error) {
	var state State
	data, err := os.ReadFile(s.path)
	if err != nil {
		return state, err
	}
	if err := json.Unmarshal(data, &state); err != nil {
		return state, fmt.Errorf("hub state is not valid JSON: %w", err)
	}
	return state, nil
}

func (s *Store) saveLocked(state State) error {
	state.UpdatedAt = time.Now().UTC()
	state.Version++
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

// Update runs fn under the store lock and persists the result. A failure leaves
// the file untouched.
func (s *Store) Update(fn func(*State) error) (State, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	state, err := s.loadLocked()
	if err != nil {
		return state, err
	}
	if err := fn(&state); err != nil {
		return state, err
	}
	if err := s.saveLocked(state); err != nil {
		return state, err
	}
	return state, nil
}

// Init creates a new network. The pool is validated here with the same rules the
// macOS side applies, because a hub that accepts 8.8.8.0/24 would hand out
// addresses that cannot work.
func Init(path, poolCIDR string, listenPort int) (State, error) {
	prefix, err := netip.ParsePrefix(poolCIDR)
	if err != nil {
		return State{}, fmt.Errorf("%q is not a CIDR network: %w", poolCIDR, err)
	}
	prefix = prefix.Masked()
	if prefix.Bits() > 29 {
		return State{}, fmt.Errorf("%s has room for fewer than 8 nodes", prefix)
	}
	if prefix.Bits() < 16 {
		return State{}, fmt.Errorf("%s is larger than /16", prefix)
	}
	if !isPrivateOrShared(prefix) {
		return State{}, fmt.Errorf("%s is not RFC 1918 or 100.64.0.0/10", prefix)
	}

	idBytes := make([]byte, 16)
	if _, err := rand.Read(idBytes); err != nil {
		return State{}, err
	}
	hubAddr := prefix.Addr().Next()
	state := State{
		NetworkID:  hex.EncodeToString(idBytes),
		Pool:       prefix.String(),
		HubAddr:    hubAddr.String(),
		ListenPort: listenPort,
		Nodes: []Node{{
			ID:         "hub",
			Name:       "Network hub",
			Role:       RoleHub,
			Address:    hubAddr.String(),
			AllowedIPs: []string{hubAddr.String() + "/32"},
		}},
		Enrollments: []EnrollmentToken{},
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return State{}, err
	}
	store := &Store{path: path}
	store.mu.Lock()
	defer store.mu.Unlock()
	if err := store.saveLocked(state); err != nil {
		return State{}, err
	}
	return store.loadLocked()
}

func isPrivateOrShared(prefix netip.Prefix) bool {
	first := prefix.Masked().Addr().Next()
	last := lastAddr(prefix)
	return (first.IsPrivate() && last.IsPrivate()) || (first.Is4() && inShared(first) && inShared(last))
}

func inShared(a netip.Addr) bool {
	b := a.As4()
	return b[0] == 100 && b[1] >= 64 && b[1] <= 127
}

func lastAddr(prefix netip.Prefix) netip.Addr {
	a := prefix.Masked().Addr().As4()
	bits := prefix.Bits()
	for i := bits; i < 32; i++ {
		a[i/8] |= 1 << (7 - uint(i%8))
	}
	return netip.AddrFrom4(a)
}

// CreateEnrollment mints a one-time token and returns its secret exactly once.
func CreateEnrollment(path, label string, role Role) (EnrollmentToken, string, error) {
	store, err := New(path)
	if err != nil {
		return EnrollmentToken{}, "", err
	}
	secretBytes := make([]byte, 32)
	if _, err := rand.Read(secretBytes); err != nil {
		return EnrollmentToken{}, "", err
	}
	secret := base64.RawURLEncoding.EncodeToString(secretBytes)
	digest := sha256.Sum256([]byte(secret))
	idBytes := make([]byte, 4)
	if _, err := rand.Read(idBytes); err != nil {
		return EnrollmentToken{}, "", err
	}
	token := EnrollmentToken{
		ID:        hex.EncodeToString(idBytes),
		Digest:    hex.EncodeToString(digest[:]),
		Label:     label,
		Role:      role,
		CreatedAt: time.Now().UTC(),
	}
	_, err = store.Update(func(s *State) error {
		s.Enrollments = append(s.Enrollments, token)
		return nil
	})
	return token, secret, err
}

var (
	ErrBadEnrollment = errors.New("enrollment token is not valid, was already used, or was revoked")
	ErrNoAddresses   = errors.New("the pool has no free address left")
	ErrNameTaken     = errors.New("a node with that name is already enrolled")
)

// Enroll registers a node idempotently: the same token and the same public key
// return the same node and address rather than allocating a second one. That is
// what makes a retried request harmless — a client whose response was lost can
// ask again.
func Enroll(path, secret, name, publicKey string) (State, Node, error) {
	store, err := New(path)
	if err != nil {
		return State{}, Node{}, err
	}
	digest := sha256.Sum256([]byte(secret))
	wanted := hex.EncodeToString(digest[:])

	var result Node
	state, err := store.Update(func(s *State) error {
		// An existing node with this key already has an address: return it.
		for _, node := range s.Nodes {
			if !node.Revoked && node.PublicKey == publicKey && publicKey != "" {
				result = node
				return nil
			}
		}

		index := -1
		for i, token := range s.Enrollments {
			stored := []byte(token.Digest)
			given := []byte(wanted)
			if len(stored) == len(given) && subtle.ConstantTimeCompare(stored, given) == 1 {
				index = i
				break
			}
		}
		if index < 0 {
			return ErrBadEnrollment
		}
		token := s.Enrollments[index]
		if token.Revoked || !token.UsedAt.IsZero() {
			return ErrBadEnrollment
		}
		for _, node := range s.Nodes {
			if node.Name == name && !node.Revoked {
				return ErrNameTaken
			}
		}

		address, ok := nextFree(s)
		if !ok {
			return ErrNoAddresses
		}
		node := Node{
			ID:         newID(),
			Name:       name,
			Role:       token.Role,
			Address:    address.String(),
			PublicKey:  publicKey,
			LastSeen:   time.Now().UTC(),
			AllowedIPs: []string{address.String() + "/32"},
		}
		s.Nodes = append(s.Nodes, node)
		s.Enrollments[index].UsedAt = time.Now().UTC()
		result = node
		return nil
	})
	if err != nil {
		return state, Node{}, err
	}
	return state, result, nil
}

func newID() string {
	b := make([]byte, 6)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// nextFree picks the lowest unused host address, skipping the network and
// broadcast addresses and every address already assigned. Lowest-first is what
// makes an address stable across retries even when the allocation is redone.
func nextFree(s *State) (netip.Addr, bool) {
	prefix, err := netip.ParsePrefix(s.Pool)
	if err != nil {
		return netip.Addr{}, false
	}
	taken := map[netip.Addr]bool{}
	for _, node := range s.Nodes {
		if node.Revoked {
			continue
		}
		if addr, err := netip.ParseAddr(node.Address); err == nil {
			taken[addr] = true
		}
	}
	broadcast := lastAddr(prefix)
	for addr := prefix.Masked().Addr().Next(); addr.Compare(broadcast) < 0; addr = addr.Next() {
		if !taken[addr] {
			return addr, true
		}
	}
	return netip.Addr{}, false
}

// Revoke removes a node's address and key. Its enrollment token is not reused:
// re-adding the device needs a new one.
func Revoke(path, id string) (State, error) {
	store, err := New(path)
	if err != nil {
		return State{}, err
	}
	return store.Update(func(s *State) error {
		for i, node := range s.Nodes {
			if node.ID == id || node.Name == id {
				if node.Role == RoleHub {
					return fmt.Errorf("the hub cannot be revoked")
				}
				s.Nodes[i].Revoked = true
				return nil
			}
		}
		return fmt.Errorf("no node %q", id)
	})
}

// UpdateEndpoint records where a node can be reached, so other nodes receive a
// working endpoint in their configuration.
func UpdateEndpoint(path, id, endpoint string) (State, error) {
	store, err := New(path)
	if err != nil {
		return State{}, err
	}
	return store.Update(func(s *State) error {
		for i, node := range s.Nodes {
			if node.ID == id {
				s.Nodes[i].Endpoint = endpoint
				s.Nodes[i].LastSeen = time.Now().UTC()
				return nil
			}
		}
		return fmt.Errorf("no node %q", id)
	})
}

// Touch records that a node was seen, which is how "online" is decided: a
// handshake within the last three minutes, not a process that happens to exist.
func Touch(path, id string) (State, error) {
	store, err := New(path)
	if err != nil {
		return State{}, err
	}
	return store.Update(func(s *State) error {
		for i, node := range s.Nodes {
			if node.ID == id {
				s.Nodes[i].LastSeen = time.Now().UTC()
				return nil
			}
		}
		return nil
	})
}

// Active returns the nodes that are not revoked, sorted by address so a client's
// peer list is stable between requests.
func (s State) Active() []Node {
	out := make([]Node, 0, len(s.Nodes))
	for _, node := range s.Nodes {
		if !node.Revoked {
			out = append(out, node)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Address < out[j].Address })
	return out
}

// Online reports whether a node handshaked recently. The window is generous
// enough to survive one missed keepalive and short enough that a node which
// vanished is reported as offline rather than as "maybe fine".
func (n Node) Online(now time.Time) bool {
	if n.LastSeen.IsZero() {
		return false
	}
	return now.Sub(n.LastSeen) < 3*time.Minute
}
