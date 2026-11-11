"""Reviews ~/deploy/compose.yaml against the Lumen Books rules. Prints every problem; exit 1 if any."""
import os, re, stat, sys
import yaml

D = "/home/player/deploy"
problems = []
bad = problems.append

path = next((os.path.join(D, f) for f in ("compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml") if os.path.exists(os.path.join(D, f))), None)
if not path:
    print("FAIL: no compose file in ~/deploy"); sys.exit(1)
try:
    doc = yaml.safe_load(open(path)) or {}
except yaml.YAMLError as e:
    print(f"FAIL: {os.path.basename(path)} is not valid YAML: {e}"); sys.exit(1)

services = doc.get("services") or {}
mysql = [(n, s) for n, s in services.items() if isinstance(s, dict) and str(s.get("image", "")).startswith("mysql")]
if len(mysql) != 1:
    print("FAIL: expected exactly one service using a mysql image"); sys.exit(1)
name, svc = mysql[0]

img = str(svc.get("image"))
if not re.fullmatch(r"mysql:8\.4\.\d+(@sha256:[0-9a-f]{64})?", img):
    bad(f"image is '{img}': pin an exact 8.4 patch version, e.g. mysql:8.4.13")

env = svc.get("environment") or {}
if isinstance(env, list):
    env = dict(e.split("=", 1) if "=" in e else (e, "") for e in env)
if "MYSQL_ROOT_PASSWORD" in env or any("PASSWORD" in k and not k.endswith("_FILE") for k in env):
    bad("a password is written in the compose file (environment): use a secret and MYSQL_ROOT_PASSWORD_FILE")
pwfile = env.get("MYSQL_ROOT_PASSWORD_FILE", "")
svc_secrets = [s if isinstance(s, str) else s.get("source") for s in (svc.get("secrets") or [])]
top_secrets = doc.get("secrets") or {}
if not pwfile.startswith("/run/secrets/"):
    bad("MYSQL_ROOT_PASSWORD_FILE must point at /run/secrets/<secret>")
else:
    sec = pwfile.rsplit("/", 1)[1]
    if sec not in svc_secrets:
        bad(f"the service doesn't list the secret '{sec}' under secrets:")
    elif sec not in top_secrets or not (top_secrets[sec] or {}).get("file"):
        bad(f"declare secret '{sec}' at the top level with file: ./secrets/...")
    else:
        f = os.path.normpath(os.path.join(D, top_secrets[sec]["file"]))
        if not os.path.isfile(f) or os.path.getsize(f) == 0:
            bad(f"the secret file {f} is missing or empty")
        elif stat.S_IMODE(os.stat(f).st_mode) & 0o077:
            bad(f"the secret file {f} is readable by others: chmod 600")
        elif open(f).read().strip() in ("hunter2", "password", "root"):
            bad("that root password is guessable")

vols = svc.get("volumes") or []
def parse_vol(v):
    if isinstance(v, str):
        parts = v.split(":")
        return {"source": parts[0], "target": parts[1] if len(parts) > 1 else parts[0], "ro": len(parts) > 2 and "ro" in parts[2].split(",")}
    return {"source": v.get("source", ""), "target": v.get("target", ""), "ro": bool(v.get("read_only"))}
pv = [parse_vol(v) for v in vols]
data = [v for v in pv if v["target"].rstrip("/") == "/var/lib/mysql"]
if not data:
    bad("data isn't on a volume: mount a named volume at /var/lib/mysql")
elif data[0]["source"].startswith((".", "/", "~")) or data[0]["source"] not in (doc.get("volumes") or {}):
    bad("mount a *named* volume at /var/lib/mysql and declare it under top-level volumes:")
conf = [v for v in pv if v["target"].rstrip("/") == "/etc/mysql/conf.d"]
if not conf:
    bad("mount ./conf.d at /etc/mysql/conf.d")
elif not conf[0]["ro"]:
    bad("mount conf.d read-only (:ro): the container shouldn't be able to change its own config")

ports = svc.get("ports") or []
def port_ok(p):
    if isinstance(p, dict):
        return str(p.get("target")) == "3306" and p.get("host_ip") == "127.0.0.1"
    return re.fullmatch(r"127\.0\.0\.1:\d+:3306(/tcp)?", str(p)) is not None
if not ports or not all(port_ok(p) for p in ports):
    bad(f"ports {ports}: publish 3306 on 127.0.0.1 only (\"127.0.0.1:3306:3306\")")

hc = svc.get("healthcheck") or {}
test = hc.get("test")
test_s = " ".join(test) if isinstance(test, list) else str(test or "")
if "mysqladmin" not in test_s or "ping" not in test_s:
    bad("add a healthcheck that runs mysqladmin ping")

if svc.get("restart") not in ("unless-stopped", "always"):
    bad("set restart: unless-stopped (or always)")
mem = svc.get("mem_limit") or (((svc.get("deploy") or {}).get("resources") or {}).get("limits") or {}).get("memory")
if not mem:
    bad("set a memory limit (mem_limit or deploy.resources.limits.memory)")

cnfs = [os.path.join(D, "conf.d", f) for f in os.listdir(os.path.join(D, "conf.d"))] if os.path.isdir(os.path.join(D, "conf.d")) else []
for f in cnfs:
    if f.endswith(".cnf") and re.search(r"^\s*bind[-_]address\s*=\s*127\.0\.0\.1", open(f).read(), re.M):
        bad(f"{os.path.basename(f)} sets bind-address=127.0.0.1: inside a container that blocks Docker's port forwarding; restrict the published port instead")

if problems:
    print(f"FAIL: {len(problems)} problem{'s' if len(problems) > 1 else ''} in {os.path.basename(path)}:")
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print(f"PASS: approved: pinned {img}, named data volume, secret-file password, 127.0.0.1-only port, healthcheck, restart policy and memory limit")
