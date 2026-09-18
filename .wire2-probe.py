import json, os, socket, subprocess, uuid, shutil, time, signal

REPO = "/Users/guofeng/Code/solo/AgentSpace"
ROOT = os.path.join(REPO, ".perf-root")
WORKER = os.path.join(REPO, ".build/debug/agentspace-worker")
shutil.rmtree(ROOT, ignore_errors=True)
space_id = str(uuid.uuid4()).upper()
os.makedirs(f"{ROOT}/Spaces")
os.makedirs(f"{ROOT}/Runtime/{space_id}")
space = {"id": space_id, "name": "W2", "username": "_agentspace_w2", "uid": 502,
         "state": "ready", "createdAt": "2026-09-19T00:00:00Z", "workspace": {"kind": "none"},
         "sharedFolders": [], "permissions": {"screenRecording": True, "accessibility": True},
         "autoStartWorker": True}
with open(f"{ROOT}/Spaces/index.json", "w") as f:
    json.dump({"spaces": [space]}, f)
env = dict(os.environ, AGENTSPACE_ROOT=ROOT)
worker = subprocess.Popen([WORKER, "--space-id", space_id, "--name", "W2",
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
alive = json.loads(send_raw(json.dumps({"protocol": 1, "requestId": "x", "token": real_token, "method": "status", "params": {}})))
print(f"  worker alive after all: ok={alive.get('ok')}")
worker.terminate()
try:
    worker.wait(timeout=5)
except Exception:
    os.killpg(os.getpgid(worker.pid), signal.SIGTERM)
shutil.rmtree(ROOT, ignore_errors=True)
