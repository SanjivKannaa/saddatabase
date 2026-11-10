"""Settings from the environment, with a local .env (chmod 600, gitignored) as fallback."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip("'\""))


_load_dotenv(ROOT / ".env")

PUBLIC_URL = os.getenv("SADDB_PUBLIC_URL", "http://127.0.0.1:8090").rstrip("/")
OAUTH_REDIRECT_URL = os.getenv("SADDB_OAUTH_REDIRECT_URL", PUBLIC_URL + "/auth/callback")
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
SECRET_KEY = os.getenv("SADDB_SECRET_KEY", "")
ALLOWED_EMAILS = [e.strip().lower() for e in os.getenv("SADDB_ALLOWED_EMAILS", "").split(",") if e.strip()]
DEV_LOGIN = os.getenv("SADDB_DEV_LOGIN", "0") == "1"
DB_PATH = Path(os.getenv("SADDB_DB", str(ROOT / "data" / "saddb.sqlite")))
BOX_SECONDS = int(os.getenv("SADDB_BOX_MINUTES", "15")) * 60          # initial lifetime of a box
EXTEND_SECONDS = int(os.getenv("SADDB_EXTEND_MINUTES", "15")) * 60    # each extension adds this
MAX_EXTENSIONS = int(os.getenv("SADDB_MAX_EXTENSIONS", "2"))          # 15 + 2 x 15 = 45 min at most
MAX_SESSIONS = int(os.getenv("SADDB_MAX_SESSIONS", "4"))
SECURE_COOKIES = PUBLIC_URL.startswith("https://")

if not SECRET_KEY:
    raise SystemExit("SADDB_SECRET_KEY is not set (put it in .env)")


def email_allowed(email: str) -> bool:
    if not ALLOWED_EMAILS:
        return True
    email = email.lower()
    return email in ALLOWED_EMAILS or any(a.startswith("@") and email.endswith(a) for a in ALLOWED_EMAILS)
