#!/usr/bin/env python3
"""
CSII-Pay Student Council Verification Portal
Zero-dependency HTTP Web Application running on port 5050.

Authorizes the Student Council account (6958082456; password from CSII_GENESIS_PASSWORD) to review
registered accounts in Firebase Firestore and execute on-chain
ACCOUNT_VERIFY transactions to unlock the 100 BDP bonus.
"""

import os
import sys
import json
import time
import secrets
import hashlib
import hmac
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
from auth import RateLimiter, audit

NODE_URL = os.environ.get("NODE_URL", "http://127.0.0.1:8000")
FIRESTORE_USERS_URL = "https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/users"
# Session store: token -> {"csrf": str, "created": float, "last_seen": float}
ACTIVE_SESSIONS = {}
SESSION_IDLE_SECONDS = 30 * 60
SESSION_MAX_SECONDS = 8 * 3600
# Cookies are Secure by default; opt out only for plain-HTTP local testing.
SECURE_COOKIE = os.environ.get("COUNCIL_INSECURE_COOKIE", "0") != "1"
LOGIN_LIMITER = RateLimiter()


def _cookie_flags():
    flags = "Path=/; HttpOnly; SameSite=Strict"
    if SECURE_COOKIE:
        flags += "; Secure"
    return flags

def _get_ssl_context():
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl._create_unverified_context()
    except Exception:
        pass
    return None

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

def get_node_groups():
    """Fetch group names from node to filter them out of student portal."""
    try:
        req = urllib.request.Request(f"{NODE_URL}/groups", headers={"User-Agent": "CouncilPortal/1.0"})
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return {g["name"] for g in data.get("groups", [])}
    except Exception as e:
        return set()


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
                # In CSII-Pay, the on-chain account identifier is the student's username/handle or doc_id.
                # Do not prioritize studentId as the account_id.
                account_id = fields.get("accountId", {}).get("stringValue", username if username else doc_id)
                full_name = fields.get("fullName", {}).get("stringValue", "N/A")
                student_id = fields.get("studentId", {}).get("stringValue", "N/A")
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

def submit_on_chain_verification(target_account, status="VERIFIED", notes="Verified by BAScii Faculty Portal"):
    """
    Sign and submit an ACCOUNT_VERIFY transaction on the blockchain.
    Enforces security: Signed with the official Faculty Keypair.
    """
    try:
        # 1. Derive Faculty Keypair
        privkey, pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)

        # 2. Get council nonce from node
        acc_req = urllib.request.Request(f"{NODE_URL}/account/{GENESIS_ACCOUNT}", headers={"User-Agent": "FacultyPortal/1.0"})
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
# HTML TEMPLATES (BAScii Matte Onyx & Pure Gold Theme)
# ─────────────────────────────────────────────────────────────────────────────
def render_login_page(error=None):
    err_html = f'<div class="error-banner">{error}</div>' if error else ''
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Faculty Portal Login — CSII-Pay</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: radial-gradient(circle at 50% 15%, #241D12 0%, #0B0C0E 100%);
      color: #ECEFF8;
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }}
    .card {{
      background: rgba(19, 21, 24, 0.85);
      border: 1px solid rgba(200, 155, 39, 0.35);
      backdrop-filter: blur(24px);
      border-radius: 24px;
      padding: 42px;
      width: 100%;
      max-width: 440px;
      box-shadow: 0 24px 48px rgba(0,0,0,0.65), 0 0 32px rgba(200, 155, 39, 0.12);
    }}
    .logo {{
      display: flex;
      align-items: center;
      gap: 14px;
      margin-bottom: 24px;
    }}
    .logo-icon {{
      width: 52px;
      height: 52px;
      background: linear-gradient(135deg, #F3C766, #C89B27);
      border-radius: 16px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 26px;
      box-shadow: 0 4px 16px rgba(200, 155, 39, 0.35);
    }}
    h1 {{ font-size: 22px; font-weight: 800; color: #FFFFFF; letter-spacing: -0.3px; }}
    p.sub {{ font-size: 13px; color: #9DA6B8; margin-bottom: 26px; line-height: 1.5; }}
    .form-group {{ margin-bottom: 20px; }}
    label {{ display: block; font-size: 11px; font-weight: 700; color: #F3C766; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.8px; }}
    input {{
      width: 100%;
      background: #0B0C0E;
      border: 1px solid rgba(200, 155, 39, 0.25);
      border-radius: 12px;
      padding: 14px 16px;
      color: #ECEFF8;
      font-size: 14px;
      font-family: inherit;
      outline: none;
      transition: all 0.2s;
    }}
    input:focus {{
      border-color: #E2AE35;
      box-shadow: 0 0 0 3px rgba(200, 155, 39, 0.2);
    }}
    .btn {{
      width: 100%;
      background: linear-gradient(135deg, #F3C766 0%, #C89B27 100%);
      color: #0B0C0E;
      border: none;
      padding: 15px;
      border-radius: 12px;
      font-size: 15px;
      font-weight: 800;
      letter-spacing: 0.3px;
      cursor: pointer;
      margin-top: 10px;
      transition: all 0.2s;
      box-shadow: 0 4px 16px rgba(200, 155, 39, 0.3);
    }}
    .btn:hover {{ opacity: 0.95; transform: translateY(-1px); }}
    .error-banner {{
      background: rgba(255, 69, 96, 0.15);
      border: 1px solid rgba(255, 69, 96, 0.35);
      color: #FFA5B4;
      padding: 12px 14px;
      border-radius: 10px;
      font-size: 13px;
      margin-bottom: 20px;
    }}
    .demo-hint {{
      margin-top: 24px;
      padding: 12px;
      background: rgba(200, 155, 39, 0.06);
      border: 1px solid rgba(200, 155, 39, 0.15);
      border-radius: 10px;
      font-size: 12px;
      color: #9DA6B8;
      text-align: center;
      line-height: 1.4;
    }}
    .demo-hint code {{ color: #F3C766; font-weight: 700; }}
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">
      <div class="logo-icon">🎓</div>
      <div>
        <h1>BAScii Faculty Portal</h1>
        <div style="font-size: 12px; color: #E2AE35; font-weight: 600;">Chulalongkorn University &bull; CSII</div>
      </div>
    </div>
    <p class="sub">Authorized Faculty Administration Portal. Inspect registered student dossiers, verify academic credentials, and approve Character Points (BDP) bonuses.</p>
    
    {err_html}

    <form method="POST" action="/login">
      <div class="form-group">
        <label>Faculty Member ID</label>
        <input type="text" name="account_id" value="6958082456" required autocomplete="username">
      </div>
      <div class="form-group">
        <label>Security Key</label>
        <input type="password" name="password" placeholder="Enter Faculty Security Key" required autocomplete="current-password">
      </div>
      <button type="submit" class="btn">Sign In to Faculty Portal</button>
    </form>

    <div class="demo-hint">
      <strong>Faculty Access:</strong> ID: <code>6958082456</code> &bull; Key: <code>123</code>
    </div>
  </div>
</body>
</html>"""

def render_dashboard_page(students, pending_count, verified_count, total_count, current_filter='all', query='', message=None, csrf_token=''):
    msg_html = f'<div class="toast-msg">✨ {message}</div>' if message else ''
    
    rows_html = ""
    if not students:
        rows_html = '<tr><td colspan="7" style="text-align:center; padding: 40px; color: #9DA6B8;">No registered student accounts matching your filter.</td></tr>'
    else:
        for s in students:
            is_ver = s["is_verified"]
            status_badge = '<span class="badge verified">✓ Verified Scholar</span>' if is_ver else '<span class="badge pending">⏳ Pending Review</span>'
            
            action_btn = f'''
            <form method="POST" action="/verify" style="display:inline-block; margin-right: 6px;">
              <input type="hidden" name="csrf_token" value="{csrf_token}">
              <input type="hidden" name="account_id" value="{s['account_id']}">
              <input type="hidden" name="doc_id" value="{s['doc_id']}">
              <input type="hidden" name="decision" value="VERIFIED">
              <button type="submit" class="action-btn verify-btn">✓ Approve & Unlock BDP</button>
            </form>
            <form method="POST" action="/verify" style="display:inline-block;">
              <input type="hidden" name="csrf_token" value="{csrf_token}">
              <input type="hidden" name="account_id" value="{s['account_id']}">
              <input type="hidden" name="doc_id" value="{s['doc_id']}">
              <input type="hidden" name="decision" value="REJECTED">
              <button type="submit" class="action-btn reject-btn" onclick="return confirm('Reject account @{s['account_id']}?');">✕ Reject</button>
            </form>
            ''' if not is_ver else '<span style="color: #00E676; font-weight: 700; font-size: 12px;">✓ 100 BDP Unlocked</span>'

            rows_html += f"""
            <tr>
              <td>
                <div style="font-weight: 700; color: #FFFFFF; font-size: 14px;">{s['full_name']}</div>
                <div style="font-size: 12px; color: #9DA6B8;">@{s['account_id']} &bull; Nick: {s['nickname']}</div>
              </td>
              <td><code class="student-id-badge">{s['student_id']}</code></td>
              <td>{status_badge}</td>
              <td>
                <div style="font-weight: 700; color: #E2AE35;">{s['csp_balance']:.2f} CSP</div>
                <div style="font-size: 11px; color: #9DA6B8;">Service Points</div>
              </td>
              <td>
                <div class="bdp-badge">
                  <span>{s['bdp_balance']:.2f} BDP</span>
                </div>
                <div style="font-size: 11px; color: {'#E2AE35' if s['frozen_bdp'] > 0 else '#5A6478'}; margin-top: 3px;">
                  🔒 {s['frozen_bdp']:.0f} Frozen
                </div>
              </td>
              <td style="font-size: 11px; color: #9DA6B8;">
                Status: <strong style="color: #ECEFF8;">{s['on_chain_status']}</strong><br>
                Nonce: #{s['on_chain_nonce']}
              </td>
              <td style="text-align: right;">{action_btn}</td>
            </tr>
            """

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="refresh" content="12">
  <title>Faculty Verification Portal — CSII-Pay</title>
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;600&display=swap" rel="stylesheet">
  <style>
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      background: radial-gradient(circle at 50% 10%, #1F190E 0%, #0B0C0E 100%);
      color: #ECEFF8;
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      padding-bottom: 60px;
    }}
    .nav {{
      background: rgba(19, 21, 24, 0.90);
      border-bottom: 1px solid rgba(200, 155, 39, 0.2);
      backdrop-filter: blur(16px);
      padding: 16px 32px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      position: sticky;
      top: 0;
      z-index: 50;
    }}
    .nav-brand {{ display: flex; align-items: center; gap: 14px; }}
    .nav-icon {{
      width: 42px;
      height: 42px;
      background: linear-gradient(135deg, #F3C766, #C89B27);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 22px;
      box-shadow: 0 4px 12px rgba(200, 155, 39, 0.3);
    }}
    .nav-title {{ font-size: 18px; font-weight: 800; color: #FFFFFF; }}
    .nav-user {{
      display: flex;
      align-items: center;
      gap: 16px;
      font-size: 13px;
    }}
    .auto-refresh-badge {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(0, 230, 118, 0.12);
      border: 1px solid rgba(0, 230, 118, 0.3);
      padding: 5px 12px;
      border-radius: 20px;
      font-size: 12px;
      color: #00E676;
      font-weight: 600;
    }}
    .pulse-dot {{
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #00E676;
      box-shadow: 0 0 8px #00E676;
    }}
    .logout-btn {{
      background: rgba(255, 69, 96, 0.15);
      color: #FF6B81;
      border: 1px solid rgba(255, 69, 96, 0.3);
      padding: 8px 14px;
      border-radius: 8px;
      text-decoration: none;
      font-weight: 700;
      transition: background 0.15s;
    }}
    .logout-btn:hover {{ background: rgba(255, 69, 96, 0.25); }}
    .container {{
      max-width: 1240px;
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
      background: #131518;
      border: 1px solid rgba(200, 155, 39, 0.2);
      border-radius: 18px;
      padding: 20px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    }}
    .stat-label {{ font-size: 11px; color: #9DA6B8; text-transform: uppercase; font-weight: 700; letter-spacing: 0.8px; }}
    .stat-val {{ font-size: 30px; font-weight: 800; margin-top: 6px; letter-spacing: -0.5px; }}
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
      background: #131518;
      border: 1px solid rgba(200, 155, 39, 0.2);
      padding: 4px;
      border-radius: 12px;
    }}
    .tab-btn {{
      padding: 8px 16px;
      border-radius: 8px;
      text-decoration: none;
      font-size: 13px;
      font-weight: 600;
      color: #9DA6B8;
      transition: all 0.15s;
    }}
    .tab-btn.active {{
      background: linear-gradient(135deg, #F3C766, #C89B27);
      color: #0B0C0E;
      font-weight: 800;
    }}
    .search-box {{
      position: relative;
      min-width: 280px;
    }}
    .search-box input {{
      width: 100%;
      background: #131518;
      border: 1px solid rgba(200, 155, 39, 0.2);
      border-radius: 12px;
      padding: 10px 16px;
      color: #ECEFF8;
      font-size: 13px;
      font-family: inherit;
      outline: none;
    }}
    .search-box input:focus {{ border-color: #E2AE35; box-shadow: 0 0 0 3px rgba(200, 155, 39, 0.15); }}
    .table-container {{
      background: #131518;
      border: 1px solid rgba(200, 155, 39, 0.2);
      border-radius: 20px;
      overflow: hidden;
      box-shadow: 0 12px 36px rgba(0,0,0,0.5);
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      text-align: left;
    }}
    th {{
      background: #0B0C0E;
      padding: 14px 20px;
      font-size: 11px;
      text-transform: uppercase;
      font-weight: 700;
      color: #F3C766;
      letter-spacing: 0.6px;
      border-bottom: 1px solid rgba(200, 155, 39, 0.2);
    }}
    td {{
      padding: 16px 20px;
      font-size: 13px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.05);
      vertical-align: middle;
    }}
    tr:hover td {{ background: rgba(200, 155, 39, 0.03); }}
    .badge {{
      display: inline-flex;
      align-items: center;
      padding: 4px 10px;
      border-radius: 8px;
      font-size: 11px;
      font-weight: 700;
    }}
    .badge.pending {{
      background: rgba(226, 174, 53, 0.15);
      color: #E2AE35;
      border: 1px solid rgba(226, 174, 53, 0.35);
    }}
    .badge.verified {{
      background: rgba(0, 230, 118, 0.15);
      color: #00E676;
      border: 1px solid rgba(0, 230, 118, 0.35);
    }}
    .student-id-badge {{
      font-family: 'JetBrains Mono', monospace;
      color: #F3C766;
      background: rgba(200, 155, 39, 0.1);
      border: 1px solid rgba(200, 155, 39, 0.25);
      padding: 3px 8px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 700;
    }}
    .bdp-badge {{
      display: inline-flex;
      align-items: center;
      background: #14120E;
      border: 1px solid #D4AF37;
      border-radius: 8px;
      padding: 4px 10px;
      color: #FFF7E2;
      font-weight: 800;
      box-shadow: 0 2px 8px rgba(212, 175, 55, 0.2);
    }}
    .action-btn {{
      padding: 8px 14px;
      border-radius: 8px;
      font-size: 12px;
      font-weight: 800;
      border: none;
      cursor: pointer;
      font-family: inherit;
      transition: all 0.15s;
    }}
    .verify-btn {{
      background: linear-gradient(135deg, #00E676 0%, #059669 100%);
      color: #0B0C0E;
    }}
    .verify-btn:hover {{ opacity: 0.95; transform: scale(1.02); }}
    .reject-btn {{
      background: rgba(255, 69, 96, 0.15);
      color: #FF6B81;
      border: 1px solid rgba(255, 69, 96, 0.35);
    }}
    .reject-btn:hover {{ background: rgba(255, 69, 96, 0.25); }}
    .toast-msg {{
      background: rgba(200, 155, 39, 0.15);
      border: 1px solid #C89B27;
      color: #FFF7E2;
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
      <div class="nav-icon">🎓</div>
      <div>
        <div class="nav-title">BAScii Faculty Verification Portal</div>
        <div style="font-size: 11px; color: #E2AE35;">Official Chulalongkorn University &bull; CSII Academic Validator</div>
      </div>
    </div>
    <div class="nav-user">
      <div class="auto-refresh-badge">
        <span class="pulse-dot"></span>
        <span id="refresh-timer">Auto-refresh: 12s</span>
      </div>
      <div>Faculty Dean: <code style="color: #F3C766; font-weight: 700;">{GENESIS_ACCOUNT}</code></div>
      <a href="/logout" class="logout-btn">Log Out</a>
    </div>
  </div>

  <div class="container">
    {msg_html}

    <div class="stats-row">
      <div class="stat-card">
        <div class="stat-label">Pending Review</div>
        <div class="stat-val" style="color: #E2AE35;">{pending_count}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Verified Scholars</div>
        <div class="stat-val" style="color: #00E676;">{verified_count}</div>
      </div>
      <div class="stat-card">
        <div class="stat-label">Total Student Accounts</div>
        <div class="stat-val" style="color: #F3C766;">{total_count}</div>
      </div>
    </div>

    <div class="search-filter-row">
      <div class="filter-tabs">
        <a href="/?filter=pending" class="tab-btn {'active' if current_filter == 'pending' else ''}">Pending Review ({pending_count})</a>
        <a href="/?filter=verified" class="tab-btn {'active' if current_filter == 'verified' else ''}">Verified Scholars ({verified_count})</a>
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
            <th>Student Dossier</th>
            <th>Chula ID</th>
            <th>Verification</th>
            <th>Service Points (CSP)</th>
            <th>Character Points (BDP)</th>
            <th>On-Chain Status</th>
            <th style="text-align: right;">Administrative Action</th>
          </tr>
        </thead>
        <tbody>
          {rows_html}
        </tbody>
      </table>
    </div>
  </div>
  <script>
    let sec = 12;
    const t = document.getElementById('refresh-timer');
    setInterval(function() {{
      const active = document.activeElement;
      if (active && (active.tagName === 'INPUT' || active.tagName === 'SELECT')) {{
        if (t) t.innerText = 'Paused (Typing)';
        return;
      }}
      sec--;
      if (t) t.innerText = 'Auto-refresh: ' + sec + 's';
      if (sec <= 0) {{
        window.location.reload();
      }}
    }}, 1000);
  </script>
</body>
</html>"""


class CouncilPortalHandler(BaseHTTPRequestHandler):
    def _session_token(self):
        cookie_header = self.headers.get("Cookie")
        if not cookie_header:
            return None
        cookie = SimpleCookie(cookie_header)
        if "council_session" not in cookie:
            return None
        return cookie["council_session"].value

    def _get_cookie_session(self):
        token = self._session_token()
        record = ACTIVE_SESSIONS.get(token) if token else None
        if not record:
            return None
        now = time.time()
        if now - record["last_seen"] > SESSION_IDLE_SECONDS or now - record["created"] > SESSION_MAX_SECONDS:
            ACTIVE_SESSIONS.pop(token, None)
            return None
        record["last_seen"] = now
        return GENESIS_ACCOUNT

    def _csrf_token(self):
        record = ACTIVE_SESSIONS.get(self._session_token() or "")
        return record["csrf"] if record else ""

    def _set_cookie_and_redirect(self, token, path="/"):
        self.send_response(302)
        self.send_header("Set-Cookie", f"council_session={token}; {_cookie_flags()}; Max-Age={SESSION_MAX_SECONDS}")
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
            token = self._session_token()
            if token:
                ACTIVE_SESSIONS.pop(token, None)
            self.send_response(302)
            self.send_header("Set-Cookie", f"council_session=; {_cookie_flags()}; Max-Age=0")
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
        node_groups = get_node_groups()

        # Combine
        combined = {}
        for fb in fb_users:
            primary_key = fb["account_id"] or fb["username"] or fb["doc_id"]
            if primary_key in node_groups or fb.get("username") in node_groups:
                continue
            combined[primary_key] = {
                "doc_id": fb["doc_id"],
                "username": fb.get("username", primary_key),
                "account_id": primary_key,
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
            if acc_id == GENESIS_ACCOUNT or acc_id in node_groups or node_acc.get("is_group_account"):
                continue

            # Robust match: direct key match or check account_id, username, doc_id, or student_id
            matched_key = None
            if acc_id in combined:
                matched_key = acc_id
            else:
                for k, s in combined.items():
                    if acc_id in (s.get("account_id"), s.get("username"), s.get("doc_id"), s.get("student_id")):
                        matched_key = k
                        break

            if matched_key:
                entry = combined[matched_key]
                entry["account_id"] = acc_id  # ensure on-chain account ID is used for actions
                entry["csp_balance"] = node_acc.get("balances", {}).get("CSP", 0.0)
                entry["bdp_balance"] = node_acc.get("balances", {}).get("BDP", 0.0)
                entry["frozen_bdp"] = node_acc.get("frozen_balances", {}).get("BDP", 0.0)
                entry["on_chain_nonce"] = node_acc.get("nonce", 0)
                entry["on_chain_status"] = "ON-CHAIN"
                entry["is_verified"] = node_acc.get("is_verified", entry["is_verified"])
                if matched_key != acc_id:
                    del combined[matched_key]
                    combined[acc_id] = entry
            else:
                combined[acc_id] = {
                    "doc_id": acc_id,
                    "username": acc_id,
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
            message=msg,
            csrf_token=self._csrf_token()
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
            client_ip = self.client_address[0]

            if not LOGIN_LIMITER.allow(f"council-login:{client_ip}", capacity=10, refill_per_sec=0.1):
                audit("council.login_rate_limited", ip=client_ip)
                html = render_login_page(error="Too many attempts. Try again in a few minutes.")
                self.send_response(429)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(html.encode("utf-8"))
                return

            expected = (GENESIS_PASSWORD or "").encode("utf-8")
            id_ok = hmac.compare_digest(account_id.encode("utf-8"), GENESIS_ACCOUNT.encode("utf-8"))
            pwd_ok = bool(expected) and hmac.compare_digest(password.encode("utf-8"), expected)
            if id_ok and pwd_ok:
                token = secrets.token_urlsafe(32)
                now = time.time()
                ACTIVE_SESSIONS[token] = {"csrf": secrets.token_urlsafe(32), "created": now, "last_seen": now}
                audit("council.login_ok", ip=client_ip)
                self._set_cookie_and_redirect(token, "/")
            else:
                audit("council.login_failed", ip=client_ip)
                html = render_login_page(error="Invalid credentials.")
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
            submitted_csrf = form.get("csrf_token", [""])[0]
            expected_csrf = self._csrf_token()
            if not expected_csrf or not hmac.compare_digest(submitted_csrf, expected_csrf):
                audit("council.csrf_rejected", ip=self.client_address[0])
                self.send_response(403)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.end_headers()
                self.wfile.write(b"Invalid or missing CSRF token. Reload the dashboard and try again.")
                return
            account_id = form.get("account_id", [""])[0].strip()
            doc_id = form.get("doc_id", [""])[0].strip()
            decision = form.get("decision", ["VERIFIED"])[0].upper()
            if decision not in ("VERIFIED", "REJECTED"):
                self._redirect("/?msg=" + urllib.parse.quote("Error: Invalid decision"))
                return

            if not account_id:
                self._redirect("/?msg=" + urllib.parse.quote("Error: Missing account ID"))
                return

            # 1. On-chain verification
            ok, msg = submit_on_chain_verification(account_id, decision)
            print(f"[FacultyPortal] On-chain verification for @{account_id}: ok={ok}, msg={msg}")

            # 2. Update Firestore
            if doc_id:
                update_firestore_verification(doc_id, is_verified=(decision == "VERIFIED"), status=decision)

            action_text = "verified and 100 BDP unlocked" if decision == "VERIFIED" else "rejected"
            self._redirect("/?msg=" + urllib.parse.quote(f"Account @{account_id} {action_text} successfully!"))
            return

        self.send_response(404)
        self.end_headers()

def run_server(port=5050):
    if not GENESIS_PASSWORD:
        print("[!] CSII_GENESIS_PASSWORD is not set; council login is disabled. See SECURITY_SETUP.md.")
    if not SECURE_COOKIE:
        print("[!] COUNCIL_INSECURE_COOKIE=1: session cookie is sent without the Secure flag (local testing only).")
    server = ThreadingHTTPServer(("0.0.0.0", port), CouncilPortalHandler)
    print(f"[*] BAScii Faculty Verification Portal listening on http://127.0.0.1:{port}...")
    server.serve_forever()

if __name__ == "__main__":
    port = int(os.environ.get("COUNCIL_PORT", 5050))
    run_server(port)
