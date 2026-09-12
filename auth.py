"""
CSII-Pay authentication primitives (stdlib only).

- load_dotenv / require_secret : read secrets from .env or the environment
- jwt_encode / jwt_decode        : HS256 JSON Web Tokens with strict validation
- TokenService                   : access + refresh token issuance, rotation,
                                   reuse detection and revocation (SQLite)
- RateLimiter / LoginThrottle    : per-IP token bucket and per-account lockout
- parse_bearer / audit           : request helpers

Every node in a deployment shares CSII_JWT_SECRET, so an access token issued by
one node verifies on any other node. That is what lets the gateway route each
request to a random node while sessions keep working.
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import sys
import threading
import time

JWT_ISSUER = "csii-pay"
JWT_AUDIENCE = "csii-pay-api"
ACCESS_TOKEN_TTL = 15 * 60            # 15 minutes
REFRESH_TOKEN_TTL = 30 * 24 * 3600    # 30 days
CLOCK_LEEWAY = 30                     # seconds
MIN_SECRET_LENGTH = 32


class AuthError(Exception):
    """Raised for any token that must not be trusted."""


# -------------------------------------------------------------
# Environment / secrets
# -------------------------------------------------------------
def load_dotenv(path: str, override: bool = False) -> bool:
    """Minimal .env loader: KEY=VALUE per line, # comments, optional quotes."""
    if not os.path.isfile(path):
        return False
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[len("export "):]
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                value = value[1:-1]
            if key and (override or key not in os.environ):
                os.environ[key] = value
    return True


def require_secret(name: str, min_length: int = MIN_SECRET_LENGTH) -> str:
    """Return a secret from the environment or exit with setup instructions."""
    value = os.environ.get(name, "")
    if len(value) < min_length:
        raise RuntimeError(
            f"{name} is missing or shorter than {min_length} characters. "
            f"Generate one with:  python3 -c \"import secrets; print(secrets.token_urlsafe(48))\"  "
            f"and put it in a .env file next to node.py (see .env.example and SECURITY_SETUP.md)."
        )
    return value


# -------------------------------------------------------------
# JWT (HS256)
# -------------------------------------------------------------
def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(data: str) -> bytes:
    padding = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + padding)


def jwt_encode(claims: dict, secret: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    signing_input = (
        _b64url_encode(json.dumps(header, separators=(",", ":"), sort_keys=True).encode("utf-8"))
        + "."
        + _b64url_encode(json.dumps(claims, separators=(",", ":"), sort_keys=True).encode("utf-8"))
    )
    sig = hmac.new(secret.encode("utf-8"), signing_input.encode("ascii"), hashlib.sha256).digest()
    return signing_input + "." + _b64url_encode(sig)


def jwt_decode(token: str, secret: str, expected_typ: str, now: float = None) -> dict:
    """Verify signature, algorithm, issuer, audience, type and time claims."""
    if not isinstance(token, str) or token.count(".") != 2:
        raise AuthError("Malformed token")
    header_b64, payload_b64, sig_b64 = token.split(".")
    try:
        header = json.loads(_b64url_decode(header_b64))
        claims = json.loads(_b64url_decode(payload_b64))
        provided_sig = _b64url_decode(sig_b64)
    except Exception:
        raise AuthError("Malformed token")

    # Algorithm confusion guard: only HS256 is ever accepted.
    if not isinstance(header, dict) or header.get("alg") != "HS256":
        raise AuthError("Unsupported token algorithm")

    signing_input = (header_b64 + "." + payload_b64).encode("ascii")
    expected_sig = hmac.new(secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    if not hmac.compare_digest(provided_sig, expected_sig):
        raise AuthError("Invalid token signature")

    if not isinstance(claims, dict):
        raise AuthError("Malformed claims")
    if claims.get("iss") != JWT_ISSUER or claims.get("aud") != JWT_AUDIENCE:
        raise AuthError("Token issuer/audience mismatch")
    if claims.get("typ") != expected_typ:
        raise AuthError("Wrong token type")

    now = time.time() if now is None else now
    try:
        exp = float(claims["exp"])
        iat = float(claims["iat"])
    except (KeyError, TypeError, ValueError):
        raise AuthError("Token missing time claims")
    if now > exp + CLOCK_LEEWAY:
        raise AuthError("Token expired")
    if iat > now + CLOCK_LEEWAY:
        raise AuthError("Token issued in the future")
    if not claims.get("sub") or not claims.get("jti"):
        raise AuthError("Token missing subject")
    return claims


# -------------------------------------------------------------
# Token service: issuance, refresh rotation, revocation
# -------------------------------------------------------------
class TokenService:
    """
    Access tokens are short-lived JWTs. Refresh tokens are long-lived JWTs
    carrying a family id; each refresh consumes the presented token and issues
    a new one in the same family. Presenting an already-consumed refresh token
    (theft indicator) revokes the whole family.

    Revocation state is per node. A shared secret keeps verification stateless
    across nodes; reuse detection and logout are best-effort on the node that
    sees the request.
    """

    def __init__(self, secret: str, db_path: str,
                 access_ttl: int = ACCESS_TOKEN_TTL, refresh_ttl: int = REFRESH_TOKEN_TTL):
        if len(secret) < MIN_SECRET_LENGTH:
            raise RuntimeError("JWT secret too short")
        self._secret = secret
        self._access_ttl = access_ttl
        self._refresh_ttl = refresh_ttl
        self._db_path = db_path
        self._lock = threading.RLock()
        self._init_db()

    def _conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self._db_path, timeout=10)
        conn.execute("PRAGMA journal_mode=WAL")
        return conn

    def _init_db(self):
        with self._lock, self._conn() as c:
            c.execute("CREATE TABLE IF NOT EXISTS revoked_jti (jti TEXT PRIMARY KEY, exp REAL NOT NULL)")
            c.execute("CREATE TABLE IF NOT EXISTS revoked_family (family TEXT PRIMARY KEY, exp REAL NOT NULL)")
            c.execute("CREATE TABLE IF NOT EXISTS consumed_refresh (jti TEXT PRIMARY KEY, family TEXT NOT NULL, exp REAL NOT NULL)")

    def _prune(self, c: sqlite3.Connection, now: float):
        c.execute("DELETE FROM revoked_jti WHERE exp < ?", (now,))
        c.execute("DELETE FROM revoked_family WHERE exp < ?", (now,))
        c.execute("DELETE FROM consumed_refresh WHERE exp < ?", (now,))

    def issue(self, account_id: str, role: str = "student", public_key: str = None, family: str = None) -> dict:
        now = time.time()
        family = family or secrets.token_urlsafe(16)
        access_claims = {
            "iss": JWT_ISSUER, "aud": JWT_AUDIENCE, "typ": "access",
            "sub": account_id, "role": role, "jti": secrets.token_urlsafe(16),
            "iat": int(now), "exp": int(now + self._access_ttl),
        }
        if public_key:
            access_claims["pk"] = public_key
        refresh_claims = {
            "iss": JWT_ISSUER, "aud": JWT_AUDIENCE, "typ": "refresh",
            "sub": account_id, "role": role, "jti": secrets.token_urlsafe(24), "fam": family,
            "iat": int(now), "exp": int(now + self._refresh_ttl),
        }
        return {
            "access_token": jwt_encode(access_claims, self._secret),
            "refresh_token": jwt_encode(refresh_claims, self._secret),
            "token_type": "Bearer",
            "expires_in": self._access_ttl,
            "refresh_expires_in": self._refresh_ttl,
        }

    def verify_access(self, token: str) -> dict:
        claims = jwt_decode(token, self._secret, expected_typ="access")
        with self._lock, self._conn() as c:
            if c.execute("SELECT 1 FROM revoked_jti WHERE jti = ?", (claims["jti"],)).fetchone():
                raise AuthError("Token revoked")
        return claims

    def refresh(self, refresh_token: str, public_key: str = None) -> dict:
        claims = jwt_decode(refresh_token, self._secret, expected_typ="refresh")
        family = claims.get("fam")
        if not family:
            raise AuthError("Malformed refresh token")
        now = time.time()
        with self._lock:
            # sqlite3's context manager rolls back on exceptions, so decide first and
            # commit each write in its own transaction before raising.
            with self._conn() as c:
                self._prune(c, now)
                family_revoked = c.execute("SELECT 1 FROM revoked_family WHERE family = ?", (family,)).fetchone() is not None
                reused = c.execute("SELECT 1 FROM consumed_refresh WHERE jti = ?", (claims["jti"],)).fetchone() is not None
                if not family_revoked and not reused:
                    c.execute("INSERT INTO consumed_refresh (jti, family, exp) VALUES (?, ?, ?)",
                              (claims["jti"], family, float(claims["exp"])))
            if family_revoked:
                raise AuthError("Session revoked")
            if reused:
                # Reuse of a rotated token is a theft indicator: revoke the whole family.
                with self._conn() as c:
                    c.execute("INSERT OR REPLACE INTO revoked_family (family, exp) VALUES (?, ?)", (family, float(claims["exp"])))
                raise AuthError("Refresh token reuse detected; session revoked")
        return self.issue(claims["sub"], role=claims.get("role", "student"), public_key=public_key, family=family)

    def revoke(self, access_claims: dict = None, refresh_token: str = None):
        now = time.time()
        with self._lock, self._conn() as c:
            self._prune(c, now)
            if access_claims:
                c.execute("INSERT OR REPLACE INTO revoked_jti (jti, exp) VALUES (?, ?)",
                          (access_claims["jti"], float(access_claims["exp"])))
            if refresh_token:
                try:
                    rc = jwt_decode(refresh_token, self._secret, expected_typ="refresh")
                except AuthError:
                    return
                c.execute("INSERT OR REPLACE INTO revoked_family (family, exp) VALUES (?, ?)",
                          (rc.get("fam", rc["jti"]), float(rc["exp"])))


# -------------------------------------------------------------
# Rate limiting
# -------------------------------------------------------------
class RateLimiter:
    """Token bucket per key (e.g. route + client IP)."""

    def __init__(self):
        self._buckets = {}
        self._lock = threading.Lock()

    def allow(self, key: str, capacity: int, refill_per_sec: float) -> bool:
        now = time.time()
        with self._lock:
            tokens, last = self._buckets.get(key, (float(capacity), now))
            tokens = min(float(capacity), tokens + (now - last) * refill_per_sec)
            if tokens < 1.0:
                self._buckets[key] = (tokens, now)
                return False
            self._buckets[key] = (tokens - 1.0, now)
            if len(self._buckets) > 50000:
                stale = [k for k, (t, l) in self._buckets.items() if now - l > 3600]
                for k in stale:
                    del self._buckets[k]
            return True


class LoginThrottle:
    """Per-account lockout with exponential backoff after repeated failures."""

    def __init__(self, free_attempts: int = 5, base_lock_seconds: int = 30, max_lock_seconds: int = 900):
        self._free = free_attempts
        self._base = base_lock_seconds
        self._max = max_lock_seconds
        self._state = {}   # account -> (failures, locked_until)
        self._lock = threading.Lock()

    def locked_for(self, account_id: str) -> int:
        """Seconds remaining on the lock, or 0."""
        with self._lock:
            failures, locked_until = self._state.get(account_id, (0, 0.0))
            remaining = int(locked_until - time.time())
            return remaining if remaining > 0 else 0

    def record_failure(self, account_id: str):
        with self._lock:
            failures, _ = self._state.get(account_id, (0, 0.0))
            failures += 1
            locked_until = 0.0
            if failures >= self._free:
                lock = min(self._max, self._base * (2 ** (failures - self._free)))
                locked_until = time.time() + lock
            self._state[account_id] = (failures, locked_until)

    def record_success(self, account_id: str):
        with self._lock:
            self._state.pop(account_id, None)


# -------------------------------------------------------------
# Request helpers
# -------------------------------------------------------------
def parse_bearer(headers) -> str:
    value = headers.get("Authorization", "") if headers else ""
    if not value:
        return ""
    parts = value.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        return ""
    return parts[1].strip()


def audit(event: str, **fields):
    """One JSON line per authentication event. Never pass secrets in fields."""
    record = {"ts": round(time.time(), 3), "event": event}
    record.update(fields)
    sys.stdout.write("[AUDIT] " + json.dumps(record, sort_keys=True) + "\n")
    sys.stdout.flush()
