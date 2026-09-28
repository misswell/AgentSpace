import json, os, pathlib, socket, subprocess, uuid, shutil, time, signal

REPO = "/Users/guofeng/Code/solo/AgentSpace"
# This probe deletes the tree it creates, so its root is pinned inside the
# checkout before anything touches it: resolved, then refused unless it is
# strictly under the repository directory.
ROOT = os.path.realpath(os.path.join(REPO, ".perf-root"))
if not ROOT.startswith(os.path.realpath(REPO) + os.sep):
    raise SystemExit("refusing to run: .perf-root is outside " + REPO)
WORKER = os.path.realpath(os.path.join(REPO, ".build", "debug", "agentspace-worker"))
shutil.rmtree(ROOT, ignore_errors=True)  # ROOT is pinned inside the checkout
space_id = str(uuid.uuid4()).upper()
os.makedirs(os.path.join(ROOT, "Spaces"))
os.makedirs(os.path.join(ROOT, "Runtime", space_id))
space = {"id": space_id, "name": "W2", "username": "_agentspace_w2", "uid": 502,
         "state": "ready", "createdAt": "2026-09-19T00:00:00Z", "workspace": {"kind": "none"},
         "sharedFolders": [], "permissions": {"screenRecording": True, "accessibility": True},
         "autoStartWorker": True}
# The registry this probe writes lives under the guarded ROOT, so it is
# resolved and checked against ROOT right here rather than trusted.
registry = pathlib.Path(ROOT, "Spaces", "index.json")
if registry.parent.resolve() != pathlib.Path(ROOT, "Spaces").resolve():
    raise SystemExit("refusing to write outside the probe root: " + str(registry))
registry.write_text(json.dumps({"spaces": [space]}), encoding="utf-8")
env = dict(os.environ, AGENTSPACE_ROOT=ROOT)
worker = subprocess.Popen([WORKER, "--space-id", space_id, "--name", "W2",
                           "--runtime-dir", ROOT, "--quiet"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                          stdin=subprocess.DEVNULL, env=env, start_new_session=True)
sock_path = os.path.join(ROOT, "Runtime", space_id, "worker.sock")
for _ in range(100):
    if os.path.exists(sock_path):
        break
    time.sleep(0.1)
time.sleep(0.2)
with open(os.path.join(ROOT, "Runtime", space_id, "token")) as f:
    real_token = f.read().strip()

def send_raw(line):
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
        return "connection closed without response"
    try:
        r = json.loads(buf.decode().splitlines()[0])
        if r.get("ok"):
            return "ok=true"
        e = r.get("error", {})
        return f"ok=false code={e.get('code')}" if e else str(r)[:80]
    except Exception:
        return f"non-JSON: {buf[:60]}"

print(f"  '{{broken'            -> {send_raw('{broken')}")
print(f"  empty line            -> {send_raw('')}")
print(f"  json array line       -> {send_raw('[1,2,3]')}")
print(f"  binary-ish            -> {send_raw(chr(0) + 'xx')}")
# The question is whether the worker is still serving after that batch, and
# `send_raw` already answers it in words — parsing its summary as JSON was a
# bug that killed the probe before its own cleanup.
alive = send_raw(json.dumps({"protocol": 1, "requestId": "x", "token": real_token, "method": "status", "params": {}}))
print(f"  worker alive after all: {alive}")
worker.terminate()
try:
    worker.wait(timeout=5)
except Exception:
    os.killpg(os.getpgid(worker.pid), signal.SIGTERM)
shutil.rmtree(ROOT, ignore_errors=True)
