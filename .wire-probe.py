import json, os, socket, subprocess, uuid, shutil, time, signal

REPO = "/Users/guofeng/Code/solo/AgentSpace"
ROOT = os.path.join(REPO, ".perf-root")
WORKER = os.path.join(REPO, ".build/debug/agentspace-worker")

shutil.rmtree(ROOT, ignore_errors=True)
space_id = str(uuid.uuid4()).upper()
os.makedirs(f"{ROOT}/Spaces")
os.makedirs(f"{ROOT}/Runtime/{space_id}")
space = {"id": space_id, "name": "Wire", "username": "_agentspace_wire", "uid": 502,
         "state": "ready", "createdAt": "2026-09-19T00:00:00Z", "workspace": {"kind": "none"},
         "sharedFolders": [], "permissions": {"screenRecording": True, "accessibility": True},
         "autoStartWorker": True}
with open(f"{ROOT}/Spaces/index.json", "w") as f:
    json.dump({"spaces": [space]}, f)

env = dict(os.environ, AGENTSPACE_ROOT=ROOT)
worker = subprocess.Popen([WORKER, "--space-id", space_id, "--name", "Wire",
                           "--runtime-dir", ROOT, "--quiet"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          stdin=subprocess.DEVNULL, env=env, start_new_session=True)
sock_path = f"{ROOT}/Runtime/{space_id}/worker.sock"
for _ in range(100):
    if os.path.exists(sock_path):
        break
    time.sleep(0.1)
time.sleep(0.2)
real_token = open(f"{ROOT}/Runtime/{space_id}/token").read().strip()

def rpc(protocol=1, token=None, method="status", params=None, raw=None):
    if raw is not None:
        line = raw
    else:
        line = json.dumps({"protocol": protocol, "requestId": str(uuid.uuid4()),
                           "token": token, "method": method,
                           "params": params if params is not None else {}})
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(sock_path)
    s.sendall((line + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        c = s.recv(4096)
        if not c:
            break
        buf += c
    s.close()
    if not buf:
        return {"NO-RESPONSE": True}
    return json.loads(buf.decode().splitlines()[0])

def summarize(r):
    if r.get("ok"):
        return "ok=true"
    e = r.get("error", {})
    if e:
        return f"ok=false code={e.get('code')}"
    if "NO-RESPONSE" in r:
        return "connection closed without response"
    return str(r)[:80]

print("=== protocol version boundary (correct token, status) ===")
for ver in (1, 0, 2, 999, "1"):
    print(f"  protocol={str(ver):<5} -> {summarize(rpc(protocol=ver, token=real_token))}")

print("=== method edge cases (correct token) ===")
for m in ("status", "noSuchMethod", ""):
    print(f"  method={m!r:<16} -> {summarize(rpc(token=real_token, method=m))}")

print("=== hello: the token-free method (per Protocol.swift) ===")
print(f"  hello, no token   -> {summarize(rpc(method='hello', token=None))}")
print(f"  hello, wrong token-> {summarize(rpc(method='hello', token='F'*64))}")

print("=== oversized params (1 MB) ===")
big = {"blob": "x" * (1024 * 1024)}
print(f"  1MB params        -> {summarize(rpc(token=real_token, method='status', params=big))}")

print("=== malformed JSON line ===")
print(f"  '{{broken'         -> {summarize(raw='{broken')}")

print("=== worker alive at the end ===")
print(f"  correct status    -> {summarize(rpc(token=real_token))}")

worker.terminate()
try:
    worker.wait(timeout=5)
except Exception:
    os.killpg(os.getpgid(worker.pid), signal.SIGTERM)
shutil.rmtree(ROOT, ignore_errors=True)
