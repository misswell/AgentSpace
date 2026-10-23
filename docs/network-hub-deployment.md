# Deploying the network hub

The hub is one small Go binary with one JSON state file. It needs a Linux or
macOS machine with a public IPv4 address and UDP reachable from every node.

## What it is

- issues one-time enrollment tokens;
- allocates a fixed IPv4 to each node;
- serves each enrolled node the peer list it configures;
- records when each node was last seen.

It does **not** carry traffic. The WireGuard interface on the hub machine does,
configured from the peer list — that is a separate, deliberate step below, and it
is the only part that needs root.

## Build and run

```bash
cd network/hub
go build -o /usr/local/bin/agentspace-hub .

sudo mkdir -p /var/lib/agentspace-hub && sudo chown "$USER" /var/lib/agentspace-hub
agentspace-hub init --pool 100.64.9.0/24 --listen-port 51820

# The control plane holds the whole network, so it binds to loopback and is
# reached through a reverse proxy or an SSH tunnel. It refuses 0.0.0.0.
agentspace-hub serve --listen 127.0.0.1:8788
```

`init` refuses a pool that is not RFC 1918 or `100.64.0.0/10`, smaller than `/29`
or larger than `/16`, because a hub that accepts them hands out addresses that
cannot work.

## Enrolling a device

```bash
agentspace-hub enroll-token --label laptop --role node
# prints the secret once; only its SHA-256 digest is stored
```

Then on the device:

```bash
curl -sS -X POST https://hub.example.com/v1/enroll \
  -H 'Content-Type: application/json' \
  -d '{"token":"<secret>","name":"laptop","publicKey":"<hex>","endpoint":"laptop.example.com:51820"}'
```

The answer carries the node's fixed address and the network's peer list. A
retried request with the same key returns the same node and address.

## WireGuard on the hub

The hub binary does not touch the kernel. Apply the peer list with `wg`:

```bash
# Private key generated locally; never sent anywhere.
wg genkey | tee /etc/wireguard/hub.key | wg pubkey > /etc/wireguard/hub.pub

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 100.64.9.1/24
ListenPort = 51820
PrivateKey = $(cat /etc/wireguard/hub.key)
EOF

# One [Peer] block per enrolled node: its public key and its exact /32.
for node in $(agentspace-hub list --json | jq -r '.nodes[] | "\(.publicKey) \(.address)"'); do
  set -- $node
  cat >> /etc/wireguard/wg0.conf <<EOF

[Peer]
PublicKey = $1
AllowedIPs = $2/32
EOF
done

wg-quick up wg0
```

Packet forwarding, if nodes must reach each other through the hub:

```bash
sysctl -w net.ipv4.ip_forward=1
iptables -A FORWARD -i wg0 -o wg0 -j ACCEPT
```

Do not add a NAT rule for the whole pool. Each peer's `AllowedIPs` is a single
host address; anything broader puts unrelated traffic on the hub.

## Firewall

Only UDP 51820 must be reachable from the internet. The control plane (8788) needs
to be reachable from devices at enrollment time and from nodes that fetch the
peer list; put it behind TLS and an authenticating proxy, or keep it on an SSH
tunnel.

## Revoking

```bash
agentspace-hub revoke laptop
# then remove that node's [Peer] block from wg0.conf and reload:
wg syncconf wg0 <(wg-quick strip wg0)
```

Revocation is not complete until the peer block is gone. A revoked node still
holds its old key, and WireGuard has no idea the hub's state file changed.

## Troubleshooting

| Symptom | What it means |
|---|---|
| `enrollment token is not valid, was already used, or was revoked` | the token was spent or revoked; mint a new one |
| `the pool has no free address left` | widen the pool; `/29` holds six addresses including the hub |
| a node shows offline right after starting | it has not handshaked; check UDP 51820 and the endpoint |
| `refusing to listen on all interfaces` | the control plane was given `0.0.0.0`; give it one address |
| a node's tunnel never handshakes | compare `wg show` on both ends; a wrong key or endpoint produces silence, not an error |
