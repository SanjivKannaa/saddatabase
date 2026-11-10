"""Google sign-in (OAuth 2.0 authorization code flow).

The Google callback may live on a different host than the site (Google only accepts redirect URIs on public
suffixes, so on the lab box the callback goes through the .ts.net name). The callback therefore hands the login
over to PUBLIC_URL with a short-lived, signed, single-use ticket, and /auth/ticket sets the session cookie there.
A nonce cookie set at /auth/login on PUBLIC_URL must match the ticket, which blocks login CSRF.
"""
import secrets
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from . import config, store

router = APIRouter()
signer = URLSafeTimedSerializer(config.SECRET_KEY, salt="saddb-auth")
_used_tickets: set[str] = set()
NONCE_COOKIE = "saddb_login_nonce"


def _safe_next(n: str | None) -> str:
    return n if n and n.startswith("/") and not n.startswith("//") else "/"


def current_user(request: Request):
    uid = request.session.get("uid")
    return store.get_user(uid) if uid else None


def require_user(request: Request) -> dict:
    u = current_user(request)
    if not u:
        raise HTTPException(401, "sign in first")
    return u


@router.get("/auth/login")
def login(request: Request, next: str = "/"):
    if not (config.GOOGLE_CLIENT_ID and config.GOOGLE_CLIENT_SECRET):
        raise HTTPException(503, "Google sign-in is not configured")
    nonce = secrets.token_urlsafe(16)
    state = signer.dumps({"n": nonce, "next": _safe_next(next)})
    q = urlencode({"client_id": config.GOOGLE_CLIENT_ID, "redirect_uri": config.OAUTH_REDIRECT_URL,
                   "response_type": "code", "scope": "openid email profile", "state": state,
                   "prompt": "select_account"})
    r = RedirectResponse("https://accounts.google.com/o/oauth2/v2/auth?" + q)
    r.set_cookie(NONCE_COOKIE, nonce, max_age=600, httponly=True, secure=config.SECURE_COOKIES, samesite="lax")
    return r


@router.get("/auth/callback")
async def callback(code: str = "", state: str = "", error: str = ""):
    if error:
        return _error(f"Google said: {error}")
    try:
        st = signer.loads(state, max_age=600)
    except (BadSignature, SignatureExpired):
        return _error("Sign-in link expired or was tampered with. Try again.")
    async with httpx.AsyncClient(timeout=15) as h:
        tok = await h.post("https://oauth2.googleapis.com/token", data={
            "code": code, "client_id": config.GOOGLE_CLIENT_ID, "client_secret": config.GOOGLE_CLIENT_SECRET,
            "redirect_uri": config.OAUTH_REDIRECT_URL, "grant_type": "authorization_code"})
        if tok.status_code != 200:
            return _error("Google rejected the sign-in code.")
        info = await h.get("https://openidconnect.googleapis.com/v1/userinfo",
                           headers={"Authorization": f"Bearer {tok.json()['access_token']}"})
    u = info.json()
    if info.status_code != 200 or not u.get("email_verified"):
        return _error("Google did not return a verified email address.")
    if not config.email_allowed(u["email"]):
        return _error(f"{u['email']} is not allowed on this sadDatabase.")
    uid = store.upsert_google_user(u["sub"], u["email"], u.get("name") or u["email"], u.get("picture", ""))
    ticket = signer.dumps({"uid": uid, "n": st["n"], "t": secrets.token_urlsafe(8)}, salt="ticket")
    return RedirectResponse(f"{config.PUBLIC_URL}/auth/ticket?{urlencode({'t': ticket, 'next': st['next']})}")


@router.get("/auth/ticket")
def ticket(request: Request, t: str, next: str = "/"):
    try:
        tk = signer.loads(t, max_age=60, salt="ticket")
    except (BadSignature, SignatureExpired):
        return _error("Sign-in ticket expired. Try again.")
    if t in _used_tickets or tk["n"] != request.cookies.get(NONCE_COOKIE):
        return _error("This sign-in was not started from this browser. Try again.")
    _used_tickets.add(t)
    request.session.clear()
    request.session["uid"] = tk["uid"]
    r = RedirectResponse(_safe_next(next))
    r.delete_cookie(NONCE_COOKIE)
    return r


@router.post("/auth/logout")
def logout(request: Request):
    request.session.clear()
    return {"ok": True}


if config.DEV_LOGIN:
    @router.get("/auth/dev")
    def dev_login(request: Request, email: str, next: str = "/"):
        """Local testing only (SADDB_DEV_LOGIN=1, direct loopback requests)."""
        if request.client.host != "127.0.0.1" or request.headers.get("x-forwarded-for"):
            raise HTTPException(403)
        uid = store.upsert_google_user(f"dev:{email}", email, email.split("@")[0], "")
        request.session.clear()
        request.session["uid"] = uid
        return RedirectResponse(_safe_next(next))


def _error(msg: str):
    return HTMLResponse(f"""<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Sign-in problem</title><body style="font:16px system-ui;max-width:520px;margin:15vh auto;padding:0 16px">
<h2>Couldn't sign you in</h2><p>{msg.replace('<', '&lt;')}</p><p><a href="{config.PUBLIC_URL}/">Back to sadDatabase</a></p>""", status_code=400)
