package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/misswell/AgentSpace/network/hub/internal/store"
)

func newTestHub(t *testing.T) (string, *store.Store) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "hub.json")
	if _, err := store.Init(path, "100.64.0.0/24", 51820); err != nil {
		t.Fatalf("Init: %v", err)
	}
	st, err := store.New(path)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return path, st
}

// post drives the real enroll handler rather than the store, so the HTTP shape a
// node meets is what is under test.
func post(t *testing.T, mux *http.ServeMux, path string, body any) *httptest.ResponseRecorder {
	t.Helper()
	encoded, _ := json.Marshal(body)
	request := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(encoded))
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	return recorder
}

func TestEnrollConsumesTheTokenAndReturnsAFixedAddress(t *testing.T) {
	mux := routesForTest(t)
	_, secret, err := store.CreateEnrollment(statePathForTest, "laptop", store.RoleNode)
	if err != nil {
		t.Fatal(err)
	}
	response := post(t, mux, "/v1/enroll", map[string]string{
		"token": secret, "name": "laptop", "publicKey": keyA,
	})
	if response.Code != 200 {
		t.Fatalf("enroll answered %d: %s", response.Code, response.Body.String())
	}
	var body struct {
		Node struct {
			Address string `json:"address"`
		} `json:"node"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Node.Address != "100.64.0.2" {
		t.Fatalf("address is %s, want 100.64.0.2", body.Node.Address)
	}

	// The same key asking again gets the same answer, not a second address.
	again := post(t, mux, "/v1/enroll", map[string]string{
		"token": secret, "name": "laptop", "publicKey": keyA,
	})
	if again.Code != 200 {
		t.Fatalf("retried enroll answered %d: %s", again.Code, again.Body.String())
	}
	var second struct {
		Node struct {
			Address string `json:"address"`
			ID      string `json:"id"`
		} `json:"node"`
	}
	_ = json.Unmarshal(again.Body.Bytes(), &second)
	if second.Node.Address != "100.64.0.2" {
		t.Fatalf("a retried enroll moved the node to %s", second.Node.Address)
	}
}

func TestEnrollRefusesAnUnknownToken(t *testing.T) {
	mux := routesForTest(t)
	response := post(t, mux, "/v1/enroll", map[string]string{
		"token": "nope", "name": "x", "publicKey": keyA,
	})
	if response.Code != 403 {
		t.Fatalf("an unknown token answered %d", response.Code)
	}
}

func TestEnrollRequiresEveryField(t *testing.T) {
	mux := routesForTest(t)
	for _, body := range []map[string]string{
		{"name": "x", "publicKey": keyA},
		{"token": "t", "publicKey": keyA},
		{"token": "t", "name": "x"},
	} {
		if response := post(t, mux, "/v1/enroll", body); response.Code != 400 {
			t.Fatalf("%v answered %d", body, response.Code)
		}
	}
}

func TestNetworkIsRefusedForAKeyThatIsNotEnrolled(t *testing.T) {
	mux := routesForTest(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/network?publicKey="+keyB, nil)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	if recorder.Code != 403 {
		t.Fatalf("an unenrolled key answered %d: %s", recorder.Code, recorder.Body.String())
	}

	// And it is served to one that is, with precise /32 routes.
	_, secret, _ := store.CreateEnrollment(statePathForTest, "laptop", store.RoleNode)
	if response := post(t, mux, "/v1/enroll", map[string]string{
		"token": secret, "name": "laptop", "publicKey": keyA,
	}); response.Code != 200 {
		t.Fatalf("enroll: %d %s", response.Code, response.Body.String())
	}
	request = httptest.NewRequest(http.MethodGet, "/v1/network?publicKey="+keyA, nil)
	recorder = httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	if recorder.Code != 200 {
		t.Fatalf("an enrolled key answered %d", recorder.Code)
	}
	var body struct {
		Network struct {
			Pool  string `json:"pool"`
			Nodes []struct {
				Address    string   `json:"address"`
				AllowedIPs []string `json:"allowedIPs"`
			} `json:"nodes"`
		} `json:"network"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Network.Pool != "100.64.0.0/24" {
		t.Fatalf("pool is %s", body.Network.Pool)
	}
	for _, node := range body.Network.Nodes {
		if len(node.AllowedIPs) != 1 || node.AllowedIPs[0] != node.Address+"/32" {
			t.Fatalf("node %s advertises %v; peers must route exact /32s", node.Address, node.AllowedIPs)
		}
	}
}

func TestHealthNeedsNoCredential(t *testing.T) {
	mux := routesForTest(t)
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	recorder := httptest.NewRecorder()
	mux.ServeHTTP(recorder, request)
	if recorder.Code != 200 {
		t.Fatalf("healthz answered %d", recorder.Code)
	}
}

// The handler set is built by the same function main uses, so a route that is
// missing here is missing in the binary too.
const (
	keyA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	keyB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

var statePathForTest string

func routesForTest(t *testing.T) *http.ServeMux {
	t.Helper()
	path, _ := newTestHub(t)
	statePathForTest = path
	return newMux(path)
}

func TestMain(m *testing.M) {
	os.Exit(m.Run())
}
