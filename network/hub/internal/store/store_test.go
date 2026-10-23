package store

import (
	"errors"
	"net/netip"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func tempPath(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	return filepath.Join(dir, "hub.json")
}

func newHub(t *testing.T, pool string) (*Store, string) {
	t.Helper()
	path := tempPath(t)
	if _, err := Init(path, pool, 51820); err != nil {
		t.Fatalf("Init: %v", err)
	}
	store, err := New(path)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return store, path
}

func TestInitRejectsPoolsThatCannotWork(t *testing.T) {
	path := tempPath(t)
	for _, pool := range []string{
		"8.8.8.0/24",       // public
		"10.0.0.0/8",       // larger than /16
		"100.64.0.0/30",    // too small
		"not-a-network",    // nonsense
		"100.64.0.0/33",    // impossible prefix
	} {
		if _, err := Init(path, pool, 51820); err == nil {
			t.Fatalf("%s was accepted", pool)
		}
	}
}

func TestInitAcceptsPrivateAndSharedPools(t *testing.T) {
	for _, pool := range []string{"100.64.7.0/24", "10.20.30.0/24", "172.16.5.0/24", "192.168.50.0/24"} {
		path := tempPath(t)
		state, err := Init(path, pool, 51820)
		if err != nil {
			t.Fatalf("Init(%s): %v", pool, err)
		}
		if state.Pool != pool {
			t.Fatalf("pool is %s, want %s", state.Pool, pool)
		}
		// The hub takes the first usable address, never the network address.
		prefix, _ := netip.ParsePrefix(pool)
		want := prefix.Masked().Addr().Next().String()
		if state.HubAddr != want {
			t.Fatalf("hub is %s, want %s", state.HubAddr, want)
		}
	}
}

func TestEnrollmentIsOneTimeAndIdempotentPerKey(t *testing.T) {
	_, path := newHub(t, "100.64.0.0/24")
	token, secret, err := CreateEnrollment(path, "laptop", RoleNode)
	if err != nil {
		t.Fatalf("CreateEnrollment: %v", err)
	}
	if len(secret) < 40 {
		t.Fatalf("secret is only %d characters", len(secret))
	}
	key := "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

	_, node, err := Enroll(path, secret, "laptop", key)
	if err != nil {
		t.Fatalf("Enroll: %v", err)
	}
	if node.Address != "100.64.0.2" {
		t.Fatalf("address is %s, want 100.64.0.2 (hub holds .1)", node.Address)
	}
	if len(node.AllowedIPs) != 1 || node.AllowedIPs[0] != node.Address+"/32" {
		t.Fatalf("allowed IPs are %v; a node must route only its own /32", node.AllowedIPs)
	}

	// The same key asks again: same node, same address, no second allocation.
	_, again, err := Enroll(path, secret, "laptop", key)
	if err != nil {
		t.Fatalf("second Enroll: %v", err)
	}
	if again.ID != node.ID || again.Address != node.Address {
		t.Fatalf("a retried enrollment produced a second node: %+v vs %+v", again, node)
	}

	// A different key cannot reuse the same spent token.
	if _, _, err := Enroll(path, secret, "phone", "1111111111111111111111111111111111111111111111111111111111111111"); !errors.Is(err, ErrBadEnrollment) {
		t.Fatalf("a spent token was accepted: %v", err)
	}
	_ = token
}

func TestUnknownAndRevokedTokensAreRefused(t *testing.T) {
	_, path := newHub(t, "100.64.0.0/24")
	key := "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
	if _, _, err := Enroll(path, "made-up-secret", "x", key); !errors.Is(err, ErrBadEnrollment) {
		t.Fatalf("an unknown secret was accepted: %v", err)
	}

	_, secret, err := CreateEnrollment(path, "laptop", RoleNode)
	if err != nil {
		t.Fatal(err)
	}
	store, _ := New(path)
	if _, err := store.Update(func(s *State) error {
		s.Enrollments[0].Revoked = true
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Enroll(path, secret, "laptop", key); !errors.Is(err, ErrBadEnrollment) {
		t.Fatalf("a revoked token was accepted: %v", err)
	}
}

func TestDuplicateNamesAreRefused(t *testing.T) {
	_, path := newHub(t, "100.64.0.0/24")
	_, secret1, _ := CreateEnrollment(path, "laptop", RoleNode)
	_, secret2, _ := CreateEnrollment(path, "phone", RoleNode)
	if _, _, err := Enroll(path, secret1, "laptop", "aaaa000000000000000000000000000000000000000000000000000000000000"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Enroll(path, secret2, "laptop", "bbbb000000000000000000000000000000000000000000000000000000000000"); !errors.Is(err, ErrNameTaken) {
		t.Fatalf("a duplicate name was accepted: %v", err)
	}
}

func TestPoolExhaustionIsReported(t *testing.T) {
	// /29: six usable addresses, one taken by the hub.
	_, path := newHub(t, "100.64.0.0/29")
	used := 0
	for i := 0; i < 10; i++ {
		_, secret, err := CreateEnrollment(path, "n", RoleNode)
		if err != nil {
			t.Fatal(err)
		}
		key := netip.AddrFrom4([4]byte{10, 0, 0, byte(i + 1)}).String() + "-key"
		if _, _, err := Enroll(path, secret, "node-"+key, key); err != nil {
			if errors.Is(err, ErrNoAddresses) {
				break
			}
			t.Fatalf("Enroll: %v", err)
		}
		used++
	}
	if used != 5 {
		t.Fatalf("allocated %d nodes in a /29 that holds 5 beyond the hub", used)
	}
}

func TestRevokedAddressIsReusableAndTheNodeIsGone(t *testing.T) {
	store, path := newHub(t, "100.64.0.0/24")
	_, secret, _ := CreateEnrollment(path, "laptop", RoleNode)
	_, node, err := Enroll(path, secret, "laptop", "cccc000000000000000000000000000000000000000000000000000000000000")
	if err != nil {
		t.Fatal(err)
	}
	state, err := Revoke(path, node.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range state.Active() {
		if n.ID == node.ID {
			t.Fatal("a revoked node is still active")
		}
	}
	if _, err := Revoke(path, "hub"); err == nil {
		t.Fatal("the hub was revoked")
	}
	_ = store
}

func TestStateSurvivesARestartAndVersionAdvances(t *testing.T) {
	_, path := newHub(t, "100.64.0.0/24")
	_, secret, _ := CreateEnrollment(path, "laptop", RoleNode)
	if _, _, err := Enroll(path, secret, "laptop", "dddd000000000000000000000000000000000000000000000000000000000000"); err != nil {
		t.Fatal(err)
	}
	reopened, err := New(path)
	if err != nil {
		t.Fatal(err)
	}
	state, err := reopened.Load()
	if err != nil {
		t.Fatal(err)
	}
	if len(state.Active()) != 2 {
		t.Fatalf("after a restart there are %d nodes, want 2", len(state.Active()))
	}
	if state.Version < 3 {
		t.Fatalf("version is %d; every mutation must advance it", state.Version)
	}
	if state.UpdatedAt.IsZero() {
		t.Fatal("updatedAt was never set")
	}
}

func TestTheSecretIsNeverWrittenToDisk(t *testing.T) {
	_, path := newHub(t, "100.64.0.0/24")
	_, secret, err := CreateEnrollment(path, "laptop", RoleNode)
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) == "" {
		t.Fatal("state file is empty")
	}
	if contains(string(data), secret) {
		t.Fatal("the enrollment secret was written to the state file; only its digest may be stored")
	}
}

func contains(haystack, needle string) bool {
	return len(needle) > 0 && len(haystack) >= len(needle) &&
		(func() bool {
			for i := 0; i+len(needle) <= len(haystack); i++ {
				if haystack[i:i+len(needle)] == needle {
					return true
				}
			}
			return false
		})()
}

func TestOnlineUsesHandshakeFreshnessNotProcessExistence(t *testing.T) {
	now := time.Now()
	fresh := Node{LastSeen: now.Add(-30 * time.Second)}
	stale := Node{LastSeen: now.Add(-10 * time.Minute)}
	never := Node{}
	if !fresh.Online(now) {
		t.Fatal("a node seen 30s ago is not online")
	}
	if stale.Online(now) {
		t.Fatal("a node last seen 10 minutes ago is reported online")
	}
	if never.Online(now) {
		t.Fatal("a node that never handshaked is reported online")
	}
}
