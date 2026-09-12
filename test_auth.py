#!/usr/bin/env python3
"""
Authentication tests for CSII-Pay.

Unit tests cover auth.py directly (JWT encoding rules, refresh rotation and
reuse detection, rate limiting, lockout). Integration tests start one real node
as a subprocess and exercise the HTTP contract:

  - unauthenticated POST to a protected route -> 401
  - placeholder signatures at /tx/submit      -> 400
  - login returns access + refresh tokens and no private key
  - token subject overrides body identity    -> 403 on mismatch
  - refresh rotation, reuse detection, logout revocation
  - account lockout after repeated failures  -> 429
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

os.environ.setdefault("CSII_GENESIS_PASSWORD", "test-genesis-secret-not-for-production")
os.environ.setdefault("CSII_JWT_SECRET", "test-jwt-secret-0123456789abcdef0123456789abcdef")

from auth import (  # noqa: E402
    AuthError, LoginThrottle, RateLimiter, TokenService, jwt_decode, jwt_encode,
    _b64url_decode, _b64url_encode, load_dotenv, parse_bearer,
)

SECRET = "unit-test-secret-0123456789abcdef0123456789abcdef"


class JwtUnitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="csii_auth_")
        self.svc = TokenService(SECRET, os.path.join(self.tmp, "auth.db"), access_ttl=60, refresh_ttl=600)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_roundtrip_and_claims(self):
        tokens = self.svc.issue("alice", role="student", public_key="ab" * 64)
        claims = self.svc.verify_access(tokens["access_token"])
        self.assertEqual(claims["sub"], "alice")
        self.assertEqual(claims["role"], "student")
        self.assertEqual(claims["pk"], "ab" * 64)
        self.assertEqual(tokens["token_type"], "Bearer")
        self.assertEqual(tokens["expires_in"], 60)

    def test_tampered_signature_rejected(self):
        token = self.svc.issue("alice")["access_token"]
        head, body, sig = token.split(".")
        flipped = ("A" if sig[0] != "A" else "B") + sig[1:]
        with self.assertRaises(AuthError):
            self.svc.verify_access(f"{head}.{body}.{flipped}")

    def test_tampered_payload_rejected(self):
        token = self.svc.issue("alice")["access_token"]
        head, body, sig = token.split(".")
        claims = json.loads(_b64url_decode(body))
        claims["sub"] = "council-impostor"
        forged_body = _b64url_encode(json.dumps(claims, separators=(",", ":"), sort_keys=True).encode())
        with self.assertRaises(AuthError):
            self.svc.verify_access(f"{head}.{forged_body}.{sig}")

    def test_alg_none_rejected(self):
        body = {"iss": "csii-pay", "aud": "csii-pay-api", "typ": "access", "sub": "alice",
                "jti": "x", "iat": int(time.time()), "exp": int(time.time()) + 60}
        header = _b64url_encode(json.dumps({"alg": "none", "typ": "JWT"}).encode())
        payload = _b64url_encode(json.dumps(body).encode())
        with self.assertRaises(AuthError):
            jwt_decode(f"{header}.{payload}.", SECRET, expected_typ="access")

    def test_wrong_secret_rejected(self):
        token = self.svc.issue("alice")["access_token"]
        with self.assertRaises(AuthError):
            jwt_decode(token, "another-secret-0123456789abcdef0123456789abcdef", expected_typ="access")

    def test_refresh_token_cannot_be_used_as_access(self):
        tokens = self.svc.issue("alice")
        with self.assertRaises(AuthError):
            self.svc.verify_access(tokens["refresh_token"])

    def test_expired_rejected(self):
        svc = TokenService(SECRET, os.path.join(self.tmp, "exp.db"), access_ttl=-120, refresh_ttl=600)
        token = svc.issue("alice")["access_token"]
        with self.assertRaises(AuthError):
            svc.verify_access(token)

    def test_refresh_rotation_and_reuse_detection(self):
        first = self.svc.issue("alice")
        second = self.svc.refresh(first["refresh_token"])
        self.assertNotEqual(first["refresh_token"], second["refresh_token"])
        self.assertEqual(self.svc.verify_access(second["access_token"])["sub"], "alice")
        # Replaying the consumed token marks the family stolen...
        with self.assertRaises(AuthError):
            self.svc.refresh(first["refresh_token"])
        # ...so the legitimate successor stops working too.
        with self.assertRaises(AuthError):
            self.svc.refresh(second["refresh_token"])

    def test_logout_revokes_access_and_refresh(self):
        tokens = self.svc.issue("alice")
        claims = self.svc.verify_access(tokens["access_token"])
        self.svc.revoke(access_claims=claims, refresh_token=tokens["refresh_token"])
        with self.assertRaises(AuthError):
            self.svc.verify_access(tokens["access_token"])
        with self.assertRaises(AuthError):
            self.svc.refresh(tokens["refresh_token"])

    def test_short_secret_refused(self):
        with self.assertRaises(RuntimeError):
            TokenService("short", os.path.join(self.tmp, "short.db"))

    def test_parse_bearer(self):
        self.assertEqual(parse_bearer({"Authorization": "Bearer abc.def.ghi"}), "abc.def.ghi")
        self.assertEqual(parse_bearer({"Authorization": "Basic abc"}), "")
        self.assertEqual(parse_bearer({}), "")

    def test_rate_limiter_and_throttle(self):
        rl = RateLimiter()
        allowed = [rl.allow("k", capacity=3, refill_per_sec=0.0) for _ in range(5)]
        self.assertEqual(allowed, [True, True, True, False, False])

        th = LoginThrottle(free_attempts=3, base_lock_seconds=30)
        for _ in range(2):
            th.record_failure("bob")
        self.assertEqual(th.locked_for("bob"), 0)
        th.record_failure("bob")
        self.assertGreater(th.locked_for("bob"), 0)
        th.record_success("bob")
        self.assertEqual(th.locked_for("bob"), 0)

    def test_dotenv_loader(self):
        path = os.path.join(self.tmp, ".env")
        with open(path, "w") as f:
            f.write("# comment\nexport CSII_TEST_A='quoted value'\nCSII_TEST_B=plain\n\nBROKEN LINE\n")
        os.environ.pop("CSII_TEST_A", None)
        os.environ["CSII_TEST_B"] = "preexisting"
        self.assertTrue(load_dotenv(path))
        self.assertEqual(os.environ["CSII_TEST_A"], "quoted value")
        self.assertEqual(os.environ["CSII_TEST_B"], "preexisting")  # never overrides


# -------------------------------------------------------------
# HTTP integration against a real node process
# -------------------------------------------------------------
NODE_PORT = 8765
UDP_PORT = 50998
BASE = f"http://127.0.0.1:{NODE_PORT}"


def http(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, {}


class NodeAuthIntegrationTests(unittest.TestCase):
    proc = None
    tmp = None

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="csii_node_auth_")
        env = dict(os.environ)
        env["PORT"] = str(NODE_PORT)  # fixed port: skips the auto-increment probe
        cls.proc = subprocess.Popen(
            [sys.executable, "node.py", "--port", str(NODE_PORT), "--udp-port", str(UDP_PORT),
             "--data-dir", cls.tmp, "--account", "6958082456", "--password", os.environ["CSII_GENESIS_PASSWORD"]],
            cwd=os.path.dirname(os.path.abspath(__file__)), env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
        )
        deadline = time.time() + 40
        while time.time() < deadline:
            try:
                status, _ = http("GET", "/status")
                if status == 200:
                    return
            except Exception:
                pass
            if cls.proc.poll() is not None:
                break
            time.sleep(0.5)
        cls.tearDownClass()
        raise RuntimeError("node did not start for auth integration tests")

    @classmethod
    def tearDownClass(cls):
        if cls.proc and cls.proc.poll() is None:
            cls.proc.terminate()
            try:
                cls.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                cls.proc.kill()
        if cls.tmp:
            shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_auth_contract(self):
        # 1. Protected route without a token
        status, body = http("POST", "/groups/create", {"account_id": "anyone", "group_name": "x"})
        self.assertEqual(status, 401, body)

        # 2. Placeholder signatures are refused at the network boundary
        status, body = http("POST", "/tx/submit", {
            "tx_id": "forged1", "sender": "6958082456", "action": "TRANSFER",
            "payload": {"recipient": "6958082456", "token": "CSP", "amount": 1},
            "nonce": 0, "timestamp": time.time(), "signature": "DIRECT_ANYTHING",
        })
        self.assertEqual(status, 400, body)
        self.assertIn("signature", body.get("error", "").lower())

        # 2b. Consensus transactions cannot be injected by clients
        status, body = http("POST", "/tx/submit", {
            "tx_id": "mint1", "sender": "SYSTEM", "action": "POA_REWARD",
            "payload": {"recipient": "6958082456", "token": "CSP", "amount": 1000},
            "nonce": 0, "timestamp": time.time(), "signature": "POA_SYSTEM_REWARD",
        })
        self.assertEqual(status, 400, body)

        # 3. Registration policy and token issuance
        status, body = http("POST", "/register", {"account_id": "auth_test_user", "password": "short"})
        self.assertEqual(status, 400, body)
        status, body = http("POST", "/register", {"account_id": "auth_test_user", "password": "correct horse battery"})
        self.assertEqual(status, 200, body)
        self.assertIn("access_token", body)
        self.assertIn("refresh_token", body)
        self.assertNotIn("private_key", body)
        self.assertTrue(body.get("salt"))
        user_access, user_refresh = body["access_token"], body["refresh_token"]

        # 4. Login returns tokens, never the private key
        status, body = http("POST", "/login", {"account_id": "6958082456", "password": os.environ["CSII_GENESIS_PASSWORD"]})
        self.assertEqual(status, 200, body)
        self.assertNotIn("private_key", body)
        council_access, council_refresh = body["access_token"], body["refresh_token"]

        # 5. Identity is bound to the token subject
        status, body = http("POST", "/activity/ping", {}, token=user_access)
        self.assertEqual(status, 200, body)
        self.assertEqual(body["proof"]["account_id"], "auth_test_user")
        status, body = http("POST", "/activity/ping", {"account_id": "6958082456"}, token=user_access)
        self.assertEqual(status, 403, body)
        status, body = http("POST", "/activity/ping", {"account_id": "6958082456"}, token=user_access[:-3] + "xyz")
        self.assertEqual(status, 401, body)

        # 6. Refresh rotation and reuse detection
        status, body = http("POST", "/auth/refresh", {"refresh_token": user_refresh})
        self.assertEqual(status, 200, body)
        rotated_access, rotated_refresh = body["access_token"], body["refresh_token"]
        self.assertNotEqual(rotated_refresh, user_refresh)
        status, body = http("POST", "/auth/refresh", {"refresh_token": user_refresh})
        self.assertEqual(status, 401, body)
        status, body = http("POST", "/auth/refresh", {"refresh_token": rotated_refresh})
        self.assertEqual(status, 401, body)  # family revoked after reuse
        status, body = http("POST", "/activity/ping", {}, token=rotated_access)
        self.assertEqual(status, 200, body)  # access token itself is still valid until expiry

        # 7. Logout revokes the access token
        status, body = http("POST", "/auth/logout", {"refresh_token": council_refresh}, token=council_access)
        self.assertEqual(status, 200, body)
        status, body = http("POST", "/activity/ping", {}, token=council_access)
        self.assertEqual(status, 401, body)
        status, body = http("POST", "/auth/refresh", {"refresh_token": council_refresh})
        self.assertEqual(status, 401, body)

        # 8. Repeated wrong passwords lock the account
        statuses = []
        for _ in range(6):
            status, _ = http("POST", "/login", {"account_id": "auth_test_user", "password": "wrong-password-1"})
            statuses.append(status)
        self.assertEqual(statuses[:5], [401] * 5, statuses)
        self.assertEqual(statuses[5], 429, statuses)


if __name__ == "__main__":
    unittest.main(verbosity=2)
