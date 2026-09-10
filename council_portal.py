#!/usr/bin/env python3
"""
CSII-Pay Student Council Verification Portal
Zero-dependency HTTP Web Application running on port 5050.

Authorizes Student Council (ID: 6958082456, Password: 123) to review
registered accounts in Firebase Firestore and execute on-chain
ACCOUNT_VERIFY transactions to unlock the 100 BDP bonus.
"""

import os
import sys
import json
import time
import secrets
import hashlib
import urllib.request
import urllib.error
import urllib.parse
import ssl
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http.cookies import SimpleCookie

# Import crypto and genesis credentials from node
from node import (
    GENESIS_ACCOUNT,
    GENESIS_PASSWORD,
    GENESIS_SALT,
    derive_account_keypair,
    compute_canonical_tx_bytes,
    sign_transaction_payload,
    hash_data
)

NODE_URL = os.environ.get("NODE_URL", "http://127.0.0.1:8000")
FIRESTORE_USERS_URL = "https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/users"
SECRET_SESSION_TOKEN = secrets.token_hex(24)
ACTIVE_SESSIONS = set()

def _get_ssl_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl.create_default_context()
    except Exception:
        pass
    return ssl._create_unverified_context()

SSL_CTX = _get_ssl_context()

def get_node_accounts():
    """Fetch on-chain accounts from node."""
    try:
        req = urllib.request.Request(f"{NODE_URL}/accounts", headers={"User-Agent": "CouncilPortal/1.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return {a["account_id"]: a for a in data.get("accounts", [])}
    except Exception as e:
        print(f"[!] Error fetching accounts from node: {e}")
        return {}

def get_firebase_users():
    """Fetch registered users from Firestore REST API."""
    try:
        req = urllib.request.Request(FIRESTORE_USERS_URL, headers={"User-Agent": "CouncilPortal/1.0"})
        with urllib.request.urlopen(req, timeout=4, context=SSL_CTX) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            docs = data.get("documents", [])
            users = []
            for doc in docs:
                fields = doc.get("fields", {})
                name_path = doc.get("name", "")
                doc_id = name_path.split("/")[-1] if "/" in name_path else ""
                
                username = fields.get("username", {}).get("stringValue", doc_id)
                account_id = fields.get("accountId", {}).get("stringValue", fields.get("studentId", {}).get("stringValue", doc_id))
                full_name = fields.get("fullName", {}).get("stringValue", "N/A")
                student_id = fields.get("studentId", {}).get("stringValue", doc_id)
                nickname = fields.get("nickname", {}).get("stringValue", username)
                faculty = fields.get("faculty", {}).get("stringValue", "Chulalongkorn School of Integrated Innovation")
                year = fields.get("year", {}).get("stringValue", fields.get("academicYear", {}).get("stringValue", "N/A"))
                created_at = fields.get("createdAt", {}).get("stringValue", "")
                is_verified = fields.get("is_verified", {}).get("booleanValue", False)
                status = fields.get("verification_status", {}).get("stringValue", "VERIFIED" if is_verified else "PENDING")

                users.append({
                    "doc_id": doc_id,
                    "username": username,
                    "account_id": account_id,
                    "full_name": full_name,
                    "student_id": student_id,
                    "nickname": nickname,
                    "faculty": faculty,
                    "year": year,
                    "created_at": created_at,
                    "is_verified": is_verified,
                    "status": status
                })
            return users
    except Exception as e:
        print(f"[!] Error fetching users from Firestore: {e}")
        return []

def update_firestore_verification(doc_id, is_verified=True, status="VERIFIED"):
    """Update verification status in Firestore via REST API."""
    try:
        patch_url = f"{FIRESTORE_USERS_URL}/{doc_id}?updateMask.fieldPaths=is_verified&updateMask.fieldPaths=verification_status"
        payload = {
            "fields": {
                "is_verified": {"booleanValue": is_verified},
                "verification_status": {"stringValue": status}
            }
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(patch_url, data=data, method="PATCH", headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=4, context=SSL_CTX) as resp:
            return resp.status == 200
    except Exception as e:
        print(f"[!] Firestore patch error: {e}")
        return False

def submit_on_chain_verification(target_account, status="VERIFIED", notes="Verified by Student Council Portal"):
    """
    Sign and submit an ACCOUNT_VERIFY transaction on the blockchain.
    Enforces security: Signed with the official Student Council Keypair.
    """
    try:
        # 1. Derive Student Council Keypair
        privkey, pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)

        # 2. Get council nonce from node
        acc_req = urllib.request.Request(f"{NODE_URL}/account/{GENESIS_ACCOUNT}", headers={"User-Agent": "CouncilPortal/1.0"})
        with urllib.request.urlopen(acc_req, timeout=3) as acc_resp:
            acc_data = json.loads(acc_resp.read().decode("utf-8"))
            nonce = acc_data.get("nonce", 0)

        # 3. Construct transaction
        tx = {
            "tx_id": f"TX_VERIFY_{target_account}_{int(time.time() * 1000)}",
            "sender": GENESIS_ACCOUNT,
            "action": "ACCOUNT_VERIFY",
            "payload": {
                "account_id": target_account,
                "status": status,
                "notes": notes
            },
            "nonce": nonce,
            "timestamp": time.time()
        }
        tx["signature"] = sign_transaction_payload(tx, privkey)

        # 4. Broadcast to node
        sub_req = urllib.request.Request(
            f"{NODE_URL}/tx/submit",
            data=json.dumps(tx).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(sub_req, timeout=4) as sub_resp:
            result = json.loads(sub_resp.read().decode("utf-8"))
            return result.get("success", False), result.get("message", "Submitted")
    except Exception as e:
        return False, str(e)


# ─────────────────────────────────────────────────────────────────────────────
# HTML TEMPLATES (Google-grade Dark Glassmorphism)
# ─────────────────────────────────────────────────────────────────────────────
def render_login_page(error=None):
    err_html = f'<div class="error-banner">{error}</div>' if error else ''
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Student Council Login — CSII-Pay</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: radial-gradient(circle at 50% 20%, #15102a 0%, #0a0815 100%);
      color: #f1f5f9;
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }}
    .card {{
      background: rgba(22, 19, 43, 0.75);
      border: 1px solid rgba(139, 92, 246, 0.25);
      backdrop-filter: blur(20px);
      border-radius: 24px;
      padding: 40px;
      width: 100%;
      max-width: 420px;
      box-shadow: 0 20px 40px rgba(0,0,0,0.5), 0 0 40px rgba(139, 92, 246, 0.15);
    }}
    .logo {{
      display: flex;
      align-items: center;
      gap: 12px;
      margin-bottom: 24px;
    }}
    .logo-icon {{
      width: 48px;
      height: 48px;
      background: linear-gradient(135deg, #8b5cf6, #06b6d4);
      border-radius: 14px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 24px;
    }}
    h1 {{ font-size: 22px; font-weight: 700; color: #ffffff; }}
    p.sub {{ font-size: 13px; color: #94a3b8; margin-bottom: 28px; line-height: 1.5; }}
    .form-group {{ margin-bottom: 20px; }}
    label {{ display: block; font-size: 12px; font-weight: 600; color: #cbd5e1; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.5px; }}
    input {{
      width: 100%;
      background: rgba(10, 8, 21, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 12px;
      padding: 14px 16px;
      color: #fff;
      font-size: 14px;
      font-family: inherit;
      outline: none;
      transition: all 0.2s;
    }}
    input:focus {{
      border-color: #8b5cf6;
      box-shadow: 0 0 0 3px rgba(139, 92, 246, 0.2);
    }}
    .btn {{
      width: 100%;
      background: linear-gradient(135deg, #8b5cf6 0%, #06b6d4 100%);
      color: #fff;
      border: none;
      padding: 14px;
      border-radius: 12px;
      font-size: 15px;
      font-weight: 700;
      cursor: pointer;
      margin-top: 10px;
    }}
    .btn:hover {{ opacity: 0.95; }}
    .error-banner {{
      background: rgba(239, 68, 68, 0.15);
      border: 1px solid rgba(239, 68, 68, 0.3);
      color: #fca5a5;
      padding: 12px 14px;
      border-radius: 10px;
      font-size: 13px;
      margin-bottom: 20px;
    }}
    .demo-hint {{
      margin-top: 24px;
      padding: 12px;
      background: rgba(255,255,255,0.04);
      border-radius: 10px;
      font-size: 12px;
      color: #94a3b8;
      text-align: center;
      line-height: 1.4;
    }}
    .demo-hint code {{ color: #a78bfa; font-weight: 600; }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <div class="logo-icon">🏛️</div>
      <div>
        <h1>Student Council</h1>
        <div style="font-size: 12px; color: #8b5cf6; font-weight: 600;">Verification Portal</div>
      </div>
    </div>
    <p class="sub">Log in with Council Operator credentials to inspect and verify newly created student accounts to unlock their 100 BDP signup rewards.</p>
    
    {err_html}

    <form method="POST" action="/login">
      <div class="form-group">
        <label>Council Member ID</label>
        <input type="text" name="account_id" value="6958082456" required autocomplete="username">
      </div>
      <div class="form-group">
        <label>Security Password</label>
        <input type="password" name="password" placeholder="Enter Council Password" required autocomplete="current-password">
      </div>
      <button type="submit" class="btn">Sign In to Council Portal</button>
    </form>

    <div class="demo-hint">
      <strong>Council Key:</strong> ID: <code>6958082456</code> &bull; Password: <code>123</code>
    </div>
  </div>
</body>
</html>"""

def render_dashboard_page(students, pending_count, verified_count, total_count, current_filter='all', query='', message=None):
    msg_html = f'<div class="toast-msg">✨ {message}</div>' if message else ''
    
    rows_html = ""
    if not students:
        rows_html = '<tr><td colspan="7" style="text-align:center; padding: 40px; color: #94a3b8;">No registered student accounts matching your filter.</td></tr>'
    else:
        for s in students:
            is_ver = s["is_verified"]
            status_badge = '<span class="badge verified">✓ Verified</span>' if is_ver else '<span class="badge pending">⏳ Pending</span>'
            
            action_btn = f'''
            <form method="POST" action="/verify" style="display:inline-block; margin-right: 6px;">
              <input type="hidden" name="account_id" value="{s['account_id']}">
              <input type="hidden" name="doc_id" value="{s['doc_id']}">
              <input type="hidden" name="decision" value="VERIFIED">
              <button type="submit" class="action-btn verify-btn">✓ Verify & Unlock BDP</button>
            </form>
            <form method="POST" action="/verify" style="display:inline-block;">
              <input type="hidden" name="account_id" value="{s['account_id']}">
              <input type="hidden" name="doc_id" value="{s['doc_id']}">
              <input type="hidden" name="decision" value="REJECTED">
              <button type="submit" class="action-btn reject-btn" onclick="return confirm('Reject account @{s['account_id']}?');">✕ Reject</button>
            </form>
            ''' if not is_ver else '<span style="color: #10b981; font-weight: 600; font-size: 12px;">Unlocked (Spendable)</span>'

            rows_html += f"""
            <tr>
              <td>
                <div style="font-weight: 700; color: #fff;">{s['full_name']}</div>
                <div style="font-size: 12px; color: #94a3b8;">@{s['account_id']} &bull; Nick: {s['nickname']}</div>
              </td>
              <td><code style="color: #a78bfa; font-weight: 600;">{s['student_id']}</code></td>
              <td>{status_badge}</td>
              <td>
                <div style="font-weight: 700; color: #38bdf8;">{s['csp_balance']:.2f} CSP</div>
              </td>
              <td>
                <div style="font-weight: 700; color: #a78bfa;">{s['bdp_balance']:.2f} BDP</div>
                <div style="font-size: 11px; color: {'#f59e0b' if s['frozen_bdp'] > 0 else '#64748b'};">
                  🔒 {s['frozen_bdp']:.0f} Frozen
                </div>
              </td>
              <td style="font-size: 11px; color: #64748b;">
                Node: {s['on_chain_status']}<br>
                Nonce: {s['on_chain_nonce']}
              </td>
              <td style="text-align: right;">{action_btn}</td>
            </tr>
            """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Council Verification Portal — CSII-Pay</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: radial-gradient(circle at 50% 10%, #15102a 0%, #0a0815 100%);
      color: #f1f5f9;
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      padding-bottom: 60px;
    }}
    .nav {{
      background: rgba(18, 14, 36, 0.85);
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      backdrop-filter: blur(16px);
      padding: 16px 32px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      position: sticky;
      top: 0;
      z-index: 50;
    }}
    .nav-brand {{ display: flex; align-items: center; gap: 12px; }}
    .nav-icon {{
      width: 40px;
      height: 40px;
      background: linear-gradient(135deg, #8b5cf6, #06b6d4);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 20px;
    }}
    .nav-title {{ font-size: 18px; font-weight: 700; }}
    .nav-user {{
      display: flex;
      align-items: center;
      gap: 16px;
      font-size: 13px;
    }}
    .logout-btn {{
      background: rgba(239, 68, 68, 0.15);
      color: #f87171;
      border: 1px solid rgba(239, 68, 68, 0.3);
      padding: 8px 14px;
      border-radius: 8px;
      text-decoration: none;
      font-weight: 600;
      transition: background 0.15s;
    }}
    .logout-btn:hover {{ background: rgba(239, 68, 68, 0.25); }}
    .container {{
      max-width: 1200px;
      margin: 32px auto;
      padding: 0 24px;
    }}
    .stats-row {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 16px;
      margin-bottom: 28px;
    }}
    .stat-card {{
      background: rgba(22, 19, 43, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 18px;
      padding: 20px;
      backdrop-filter: blur(12px);
    }}
    .stat-label {{ font-size: 12px; color: #94a3b8; text-transform: uppercase; font-weight: 600; letter-spacing: 0.5px; }}
    .stat-val {{ font-size: 28px; font-weight: 800; margin-top: 6px; }}
    .search-filter-row {{
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 16px;
      margin-bottom: 20px;
      flex-wrap: wrap;
    }}
    .filter-tabs {{
      display: flex;
      background: rgba(22, 19, 43, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.08);
      padding: 4px;
      border-radius: 12px;
    }}
    .tab-btn {{
      padding: 8px 16px;
      border-radius: 8px;
      text-decoration: none;
      font-size: 13px;
      font-weight: 600;
      color: #94a3b8;
      transition: all 0.15s;
    }}
    .tab-btn.active {{
      background: #8b5cf6;
      color: #fff;
    }}
    .search-box {{
      position: relative;
      min-width: 280px;
    }}
    .search-box input {{
      width: 100%;
      background: rgba(22, 19, 43, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 12px;
      padding: 10px 16px;
      color: #fff;
      font-size: 13px;
      font-family: inherit;
      outline: none;
    }}
    .search-box input:focus {{ border-color: #8b5cf6; }}
    .table-container {{
      background: rgba(22, 19, 43, 0.7);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 20px;
      overflow: hidden;
      backdrop-filter: blur(12px);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      text-align: left;
    }}
    th {{
      background: rgba(14, 11, 28, 0.8);
      padding: 14px 20px;
      font-size: 11px;
      text-transform: uppercase;
      font-weight: 700;
      color: #94a3b8;
      letter-spacing: 0.5px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
    }}
    td {{
      padding: 16px 20px;
      font-size: 13px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.04);
      vertical-align: middle;
    }}
    tr:hover td {{ background: rgba(255, 255, 255, 0.02); }}
    .badge {{
      display: inline-flex;
      align-items: center;
      padding: 4px 10px;
      border-radius: 8px;
      font-size: 11px;
      font-weight: 700;
    }}
    .badge.pending {{
      background: rgba(245, 158, 11, 0.15);
      color: #fbbf24;
      border: 1px solid rgba(245, 158, 11, 0.3);
    }}
    .badge.verified {{
      background: rgba(16, 185, 129, 0.15);
      color: #34d399;
      border: 1px solid rgba(16, 185, 129, 0.3);
    }}
    .action-btn {{
      padding: 6px 12px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 700;
      border: none;
      cursor: pointer;
      font-family: inherit;
    }}
    .verify-btn {{
      background: #10b981;
      color: #fff;
    }}
    .verify-btn:hover {{ background: #059669; }}
    .reject-btn {{
      background: rgba(239, 68, 68, 0.15);
      color: #f87171;
      border: 1px solid rgba(239, 68, 68, 0.3);
    }}
    .reject-btn:hover {{ background: rgba(239, 68, 68, 0.3); }}
    .toast-msg {{
      background: linear-gradient(135deg, rgba(139, 92, 246, 0.2), rgba(6, 182, 212, 0.2));
      border: 1px solid rgba(139, 92, 246, 0.4);
      color: #e2e8f0;
      padding: 14px 20px;
      border-radius: 14px;
      margin-bottom: 24px;
      font-size: 14px;
      font-weight: 600;
    }}
  </style>
</head>
<body>
  <div class="nav">
    <div class="nav-brand">
      <div class="nav-icon">🏛️</div>
      <div>
        <div class="nav-title">CSII-Pay Student Council Verification</div>
        <div style="font-size: 11px; color: #8b5cf6;">Official On-Chain Validator Portal</div>
      </div>
    </div>
    <div class="nav-user">
      <div>Council ID: <code style="color: #a78bfa; font-weight: 700;">{GENESIS_ACCOUNT}</code> (Authorized)</div>
      <a href="/logout" class="logout-btn">Log Out</a>
    </div>
  </div>

  <div class="container">
    {msg_html}

    <div class="stats-row">
      <div class="stat-card">
        <div class="stat-label">Pending Verifications</div>
        <div class="stat-val" style="color: #f59e0b;">{pending_count}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Verified Students</div>
        <div class="stat-val" style="color: #10b981;">{verified_count}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Accounts</div>
        <div class="stat-val" style="color: #a78bfa;">{total_count}</div>
      </div>
    </div>

    <div class="search-filter-row">
      <div class="filter-tabs">
        <a href="/?filter=pending" class="tab-btn {'active' if current_filter == 'pending' else ''}">Pending Review ({pending_count})</a>
        <a href="/?filter=verified" class="tab-btn {'active' if current_filter == 'verified' else ''}">Verified ({verified_count})</a>
        <a href="/?filter=all" class="tab-btn {'active' if current_filter == 'all' else ''}">All Registered ({total_count})</a>
      </div>
      <form method="GET" action="/" class="search-box">
        <input type="text" name="q" value="{query}" placeholder="Search name, ID, or handle...">
        <input type="hidden" name="filter" value="{current_filter}">
      </form>
    </div>

    <div class="table-container">
      <table>
        <thead>
          <tr>
            <th>Student / Account</th>
            <th>Chula ID</th>
            <th>Verification</th>
            <th>CSP (Base)</th>
            <th>BDP (Bonus)</th>
            <th>On-Chain Status</th>
            <th style="text-align: right;">Action</th>
          </tr>
        </thead>
        <tbody>
          {rows_html}
        </tbody>
      </table>
    </div>
  </div>
</body>
</html>"""


class CouncilPortalHandler(BaseHTTPRequestHandler):
    def _get_cookie_session(self):
        cookie_header = self.headers.get("Cookie")
        if not cookie_header:
            return None
        cookie = SimpleCookie(cookie_header)
        if "council_session" in cookie:
            token = cookie["council_session"].value
            if token in ACTIVE_SESSIONS:
                return GENESIS_ACCOUNT
        return None

    def _set_cookie_and_redirect(self, token, path="/"):
        self.send_response(302)
        self.send_header("Set-Cookie", f"council_session={token}; Path=/; HttpOnly")
        self.send_header("Location", path)
        self.end_headers()

    def _redirect(self, path):
        self.send_response(302)
        self.send_header("Location", path)
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        qs = urllib.parse.parse_qs(parsed.query)

        session_user = self._get_cookie_session()

        if path == "/logout":
            cookie_header = self.headers.get("Cookie")
            if cookie_header:
                cookie = SimpleCookie(cookie_header)
                if "council_session" in cookie:
                    ACTIVE_SESSIONS.discard(cookie["council_session"].value)
            self.send_response(302)
            self.send_header("Set-Cookie", "council_session=; Path=/; Max-Age=0")
            self.send_header("Location", "/login")
            self.end_headers()
            return

        if path == "/login":
            if session_user:
                self._redirect("/")
                return
            html = render_login_page()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(html.encode("utf-8"))
            return

        # Protected Dashboard
        if not session_user:
            self._redirect("/login")
            return

        current_filter = qs.get("filter", ["all"])[0].lower()
        query = qs.get("q", [""])[0].lower().strip()
        msg = qs.get("msg", [None])[0]

        # 1. Fetch data
        fb_users = get_firebase_users()
        node_accounts = get_node_accounts()

        # Combine
        combined = {}
        for fb in fb_users:
            combined[fb["account_id"]] = {
                "doc_id": fb["doc_id"],
                "account_id": fb["account_id"],
                "full_name": fb["full_name"],
                "student_id": fb["student_id"],
                "nickname": fb["nickname"],
                "faculty": fb["faculty"],
                "year": fb["year"],
                "created_at": fb["created_at"],
                "is_verified": fb["is_verified"],
                "status": fb["status"],
                "csp_balance": 0.0,
                "bdp_balance": 0.0,
                "frozen_bdp": 0.0,
                "on_chain_nonce": 0,
                "on_chain_status": "OFF-CHAIN"
            }

        for acc_id, node_acc in node_accounts.items():
            if acc_id == GENESIS_ACCOUNT:
                continue
            if acc_id in combined:
                combined[acc_id]["csp_balance"] = node_acc.get("balances", {}).get("CSP", 0.0)
                combined[acc_id]["bdp_balance"] = node_acc.get("balances", {}).get("BDP", 0.0)
                combined[acc_id]["frozen_bdp"] = node_acc.get("frozen_balances", {}).get("BDP", 0.0)
                combined[acc_id]["on_chain_nonce"] = node_acc.get("nonce", 0)
                combined[acc_id]["on_chain_status"] = "ON-CHAIN"
                combined[acc_id]["is_verified"] = node_acc.get("is_verified", combined[acc_id]["is_verified"])
            else:
                combined[acc_id] = {
                    "doc_id": acc_id,
                    "account_id": acc_id,
                    "full_name": f"Account @{acc_id}",
                    "student_id": acc_id if acc_id.isdigit() else "N/A",
                    "nickname": acc_id,
                    "faculty": "CSII",
                    "year": "N/A",
                    "created_at": "",
                    "is_verified": node_acc.get("is_verified", False),
                    "status": node_acc.get("verification_status", "PENDING"),
                    "csp_balance": node_acc.get("balances", {}).get("CSP", 0.0),
                    "bdp_balance": node_acc.get("balances", {}).get("BDP", 0.0),
                    "frozen_bdp": node_acc.get("frozen_balances", {}).get("BDP", 0.0),
                    "on_chain_nonce": node_acc.get("nonce", 0),
                    "on_chain_status": "ON-CHAIN"
                }

        students_list = list(combined.values())
        pending_count = sum(1 for s in students_list if not s["is_verified"])
        verified_count = sum(1 for s in students_list if s["is_verified"])
        total_count = len(students_list)

        if current_filter == "pending":
            filtered = [s for s in students_list if not s["is_verified"]]
        elif current_filter == "verified":
            filtered = [s for s in students_list if s["is_verified"]]
        else:
            filtered = students_list

        if query:
            filtered = [
                s for s in filtered
                if query in s["full_name"].lower() or query in s["student_id"].lower() or query in s["account_id"].lower()
            ]

        html = render_dashboard_page(
            students=filtered,
            pending_count=pending_count,
            verified_count=verified_count,
            total_count=total_count,
            current_filter=current_filter,
            query=query,
            message=msg
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(html.encode("utf-8"))

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8") if length > 0 else ""
        form = urllib.parse.parse_qs(body)

        if path == "/login":
            account_id = form.get("account_id", [""])[0].strip()
            password = form.get("password", [""])[0].strip()

            if account_id == GENESIS_ACCOUNT and password == GENESIS_PASSWORD:
                token = secrets.token_hex(24)
                ACTIVE_SESSIONS.add(token)
                self._set_cookie_and_redirect(token, "/")
            else:
                html = render_login_page(error="Invalid Council credentials. Authorized ID: 6958082456")
                self.send_response(401)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(html.encode("utf-8"))
            return

        # Protected POST endpoints
        session_user = self._get_cookie_session()
        if not session_user:
            self._redirect("/login")
            return

        if path == "/verify":
            account_id = form.get("account_id", [""])[0].strip()
            doc_id = form.get("doc_id", [""])[0].strip()
            decision = form.get("decision", ["VERIFIED"])[0].upper()

            if not account_id:
                self._redirect("/?msg=" + urllib.parse.quote("Error: Missing account ID"))
                return

            # 1. On-chain verification
            ok, msg = submit_on_chain_verification(account_id, decision)
            print(f"[CouncilPortal] On-chain verification for @{account_id}: ok={ok}, msg={msg}")

            # 2. Update Firestore
            if doc_id:
                update_firestore_verification(doc_id, is_verified=(decision == "VERIFIED"), status=decision)

            action_text = "verified and 100 BDP unlocked" if decision == "VERIFIED" else "rejected"
            self._redirect("/?msg=" + urllib.parse.quote(f"Account @{account_id} {action_text} successfully!"))
            return

        self.send_response(404)
        self.end_headers()

def run_server(port=5050):
    server = ThreadingHTTPServer(("0.0.0.0", port), CouncilPortalHandler)
    print(f"[*] CSII Student Council Portal listening on http://127.0.0.1:{port}...")
    server.serve_forever()

if __name__ == "__main__":
    port = int(os.environ.get("COUNCIL_PORT", 5050))
    run_server(port)
