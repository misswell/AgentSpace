# Virtual network and remote API

AgentSpace can put the Mac, the machine that drives its agents, and a network
hub on one private IPv4 network, so a remote client reaches a **fixed address**
no matter which network either side is on. **No tunnel ships** — the system
extension was built, signed, notarized and then removed when macOS 26 refused
its configuration in every form measured (§399); a virtual address that other
machines can reach comes from a mesh VPN or the user's own WireGuard, never
from this product.

Two independent services are involved and they start and stop separately:

| Service | What it does | Where it runs |
|---|---|---|
| **Address planning** | a stored pool with fixed IPv4 addresses for the hub, the controller and this Mac | a configuration store, no data plane of its own |
| **Remote API** | HTTP JSON over loopback (default) or a virtual address | the app, which owns the listener while it is open |

## Address planning

Automatic mode picks a `/24` at random from `100.64.0.0/10` (RFC 6598) first,
then RFC 1918, and rejects any candidate that overlaps this Mac's interfaces or
routing table. The layout inside the pool is fixed:

```text
pool         100.64.7.0/24
hub          .1          the coordination service
controller   .2          the machine that drives the agents
this Mac     .11         AgentSpace
other nodes  .3, .4, …   allocated lowest-first
```

The pool is stored, not re-derived, so the addresses do not move between
launches. `agentspace network status` prints it and `agentspace network enable`
chooses it.

### What is refused, and what an override exists for

| Refusal | Override |
|---|---|
| a pool outside RFC 1918 and `100.64.0.0/10` | `--allow-non-private-pool` (deliberate, documented) |
| a pool that overlaps a local network | `--allow-overlap` — precise host routes keep unrelated traffic out of the tunnel |
| an address this Mac already holds | **none.** No route can make two interfaces hold one address |
| a duplicate address between nodes | none |
| the network/broadcast address of the pool | none |
| a pool narrower than /29 or wider than /16 | none |
| an API port outside 1024–65535 | none |

`agentspace network doctor` reports which checks actually ran. If this Mac's
interfaces or routes cannot be read, overlap is reported as **unverified**, never
as clean.

### Changing addresses

A change is previewed and committed, and the previous version is kept:

```bash
agentspace network configure --local 100.64.7.12   # prints the migration plan
agentspace network status                          # previousVersion is recorded
```

The migration plan names every address change and every offline node. A node
that is offline keeps its old address and is reported as offline rather than
claimed migrated. Applying a new pool to a running tunnel is the app's job
(Settings → Virtual Network), which shows the same preview before it writes.

## Routes

Every peer is routed as an exact `/32`. The pool itself is never routed: a
physical LAN that happens to use the same `/24` keeps working, and only the
virtual addresses enter the tunnel.

## API

```bash
agentspace api-token create --name ci --scope observe
# → prints the secret once
agentspace api enable --port 8787
agentspace api status
```

The listener binds to this Mac's virtual address, or to `127.0.0.1` with
`--loopback`. There is no option to bind `0.0.0.0`; the code has no case for it.

When the tunnel is down the virtual address is not assigned, and the API refuses
to start rather than falling back to a physical interface.

### Endpoints

| Method | Path | Scope |
|---|---|---|
| GET | `/healthz` | none |
| GET | `/v1/network/status` | read |
| GET | `/v1/agents` | read |
| GET | `/v1/agents/{uuid}/status` | read |
| GET | `/v1/agents/{uuid}/apps` | read |
| POST | `/v1/agents/{uuid}/screenshot` | observe |
| GET | `/v1/agents/{uuid}/windows` | observe |
| POST | `/v1/agents/{uuid}/input` | control |
| POST | `/v1/agents/{uuid}/launch` | control |
| POST | `/v1/agents/{uuid}/quit` | control |

`{uuid}` must be an Agent UUID. A worker socket path, a session token or a method
name in that position is refused at the routing layer.

`exec` has no HTTP endpoint. It is a Worker method with its own refusal list, and
exposing it over a network would put it behind a different gate than the one it
was designed for.

### Authentication

A Bearer token with at least 256 bits of entropy, stored only as a SHA-256 digest
in `<root>/Network/api-tokens.json` (mode 0600). Scopes are `read`, `observe`,
`control` and `exec`, and they imply the read-only scopes below them.

`GET /healthz` is the one unauthenticated endpoint: it reports how many agents
exist, never anything about one.

Tokens are created, revoked and rotated locally:

```bash
agentspace api-token list
agentspace api-token rotate <id>    # old secret stops working immediately
```

### Errors

Every failure is JSON with the underlying code preserved:

```json
{"ok": false, "error": {"code": "SESSION_IS_CONSOLE", "message": "…",
                        "recoverable": false, "requestId": "…"}}
```

| Status | Meaning |
|---|---|
| 400 | malformed request or an invalid action |
| 401 | missing or invalid token |
| 403 | the token does not grant the scope |
| 404 | no agent with that id |
| 409 | the session cannot accept that operation right now |
| 429 | rate limited (per token and per agent) |
| 503 | worker offline, or a permission the worker needs is missing |
| 504 | the worker timed out |

A worker that is not running is **503**, never a 200 with an empty body. There is
no fallback to the human's desktop anywhere on this path.

## The hub

The hub coordinates: it issues one-time enrollment tokens, allocates addresses,
and serves each node the peer list. It carries no traffic itself; the WireGuard
interface does.

```bash
network/hub/agentspace-hub init --pool 100.64.9.0/24
network/hub/agentspace-hub enroll-token --label laptop --role node
network/hub/agentspace-hub serve --listen 127.0.0.1:8788
network/hub/agentspace-hub list
network/hub/agentspace-hub revoke laptop
```

- Enrollment is **idempotent per public key**: a retried request returns the same
  node and the same address instead of allocating a second one.
- A token is spent on first use; re-adding a device needs a new one.
- Revoking a node removes its address and key. The hub cannot be revoked.
- "Online" means a handshake within three minutes, never "the process exists".
- The control plane refuses to listen on `0.0.0.0`.

See [network-hub-deployment.md](network-hub-deployment.md) for a server setup.

## Verifying it

`scripts/network-e2e.sh` builds the hub, starts one on an ephemeral port, enrolls
two nodes with real keys, generates both WireGuard configurations **from
`AgentSpaceCore`**, and hands them to a real `wireguard-go` with a fake TUN. It
requires that both sides actually handshake and that one ICMP packet crosses in
each direction. Exit 3 means Go was unavailable, so nothing was verified.

The kernel interface is the only simulated part. The WireGuard implementation,
its crypto, its UDP transport and the hub are the shipping ones.

## Where the API listens

The API binds **`127.0.0.1` by default**. That is a deliberate product decision,
not a placeholder:

- loopback exists on every Mac before any interface comes up, so the API works
  with Wi-Fi off, no cable, no VPN — the owner's requirement was 「断网也能用」;
- it is never reachable from another machine, which is the right default for a
  control surface that can drive a desktop;
- it needs no entitlement, no system extension and no approval.

The **app owns the listener**: while AgentSpace is open it reconciles
`api.json` into a real `APIServer` every few seconds, so `agentspace api
enable` takes effect without a relaunch and the settings page reports the
address a person can actually call. Closing the app closes the listener; no
LaunchAgent starts it.

A virtual address is **opt-in** (`agentspace api enable --virtual`, or the same
choice in the app). It only starts when that address is really on an interface, so
a tunnel that is down produces a refusal rather than a listener somewhere else.

### Reaching it from another machine

Two supported ways, neither of which AgentSpace implements itself:

1. **An existing mesh VPN.** If this Mac already runs Tailscale or ZeroTier, bind
   the API to that interface's address and use the address it assigned. This was
   measured: the API bound `100.64.0.1:8787` (Tailscale), answered `200` there,
   and refused the same port on `192.168.31.60` and `10.10.10.246`. Fixed IPv4,
   encryption and NAT traversal all come from the tool that already does them.
2. **Your own WireGuard.** `agentspace network status` prints the exact host
   routes and the UAPI configuration the product generates; a self-hosted hub is
   in `network/hub`.

### What AgentSpace does not ship

An earlier attempt built a packet-tunnel **system extension** into the app. It
signed, notarized and activated (`activated enabled`), but saving its
configuration was refused on macOS 26 with `NEVPNErrorDomain 5 permission
denied` — measured with no entitlement, with the full entitlement set, with
`allow-vpn`, and through LaunchServices. Tailscale avoids this with a root
daemon; adding one would have meant a new privileged operation and a fresh
security review. The extension was removed rather than shipped half-working, and
`systemextensionsctl list` no longer contains an AgentSpace tunnel.

## What this does not do

- **IPv6.** The toggle exists and is stored; only IPv4 is implemented. A pool or
  an address that needs IPv6 is not claimed to work.
- **A hosted service.** The hub is self-hosted. There is no AgentSpace-run
  coordination service, so `network connect` without a hub of your own has
   nothing to connect to.
- **NAT traversal beyond WireGuard's own.** If UDP cannot reach the hub, the
   tunnel will not come up, and AgentSpace will say so rather than claim a
   connection. An HTTPS relay is not implemented.
- **Desktop streaming over HTTP.** Screenshots are one-shot PNG requests. There
   is no video endpoint.

## Port map: an agent account's local APIs, callable from the main system

The one thing the remote API does not do is carry the *agent account's own*
services — an API the agent runs locally inside its session. That is the port
map's job, and it needs no tunnel, no virtual network and no network at all.

```bash
agentspace ports AgentUse            # what this account listens on, and what is mapped
agentspace ports AgentUse map 3000   # → mapped onto a generated port, e.g. 127.0.0.1:45318
agentspace ports AgentUse unmap 3000
```

- Every mapping gets a **generated port** in 45,000–46,999 (below the kernel's
  ephemeral range, clear of the sign-in relay's 47,000–47,999), derived from
  the account id and the internal port, and **stored** with the mapping so it
  cannot move. The main system then calls `http://127.0.0.1:<generated>`.
- The forwarder runs **inside the AgentSpace app** while it is open, on
  `127.0.0.1:<generated>` → the account's `127.0.0.1:<internal>`. All accounts
  on this Mac share one kernel network stack, which is why that one hop
  reaches a service in another account's session at all.
- **Ownership is proven, not assumed.** Because the stack is shared,
  `127.0.0.1:<internal>` cannot say whose service it is; the forwarder asks
  the account's own worker (`ports.list`, answered by lsof as that account's
  uid) before every accepted connection, and refuses when the account no
  longer listens on the port. A worker that cannot be asked means no evidence,
  and no evidence means no bytes.
- `map` verifies ownership up front too, and refuses ports bound only to
  non-loopback addresses — an alias could not reach those with no network.

### Why the generated address is a port, not a per-account IP

A distinct loopback IP is not available to an unprivileged process on macOS.
Only addresses actually assigned to `lo0` can be bound — `127.0.0.1` by
default — and `bind()` on any other `127.x.y.z` answers **errno 49
(EADDRNOTAVAIL, "Can't assign requested address")**, measured 2026-10-25 with
a plain POSIX socket on `127.0.0.2`, `127.1.2.3` and `127.100.231.7`.
Assigning more addresses to `lo0` is `ifconfig lo0 alias`, which is root —
exactly the road §399 declined for the tunnel. (§399 row 1354's "the kernel
routes 127.0.0.2" is about *routing*: a connect gets refused rather than
unreachable. It says nothing about binding.) So the generated address is a
port on 127.0.0.1, and this section is where that decision is written down.
