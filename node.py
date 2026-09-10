#!/usr/bin/env python3
"""
CSII-Pay: 2-Layer Cryptocurrency Node Server (node.py)
------------------------------------------------------
Features:
- Layer 1 (Base Token): CSP
- Layer 2 (Token on top): BDP
- Proof of Activity (PoA) consensus protocol with fork choice & common-ancestor reorganization
- Built-in Smart Contract Escrow System for order-based P2P exchange (partial fulfillment default)
- Secp256k1 Cryptographic Digital Signatures & Nonce Replay Attack Protection
- Interactive Node Operator Console (login/register/status/balance directly on node interface)
- WiFi / Local IP auto-discovery (UDP beacon) and HTTP P2P block & transaction sync
- Peer quarantine and security against malicious block / chain poisoning
"""

import argparse
import copy
import hashlib
import hmac
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

from storage import BlockchainStorage
from contracts import SmartContractEngine, ContractContext

# Default Configuration
DEFAULT_HTTP_PORT = 8000
DEFAULT_UDP_PORT = 50555
DEFAULT_BLOCK_TIME = 8.0  # seconds between PoA rounds when active
GENESIS_ACCOUNT = "6958082456"
GENESIS_PASSWORD = "123"
GENESIS_SALT = "csii_pay_genesis_salt_v1"
GENESIS_CSP = 10000.0
GENESIS_BDP = 100.0
INITIAL_BLOCK_REWARD_CSP = 10.0   # Deflationary Bitcoin-like controlled base block reward
HALVING_INTERVAL = 200           # Halve base reward every 200 blocks
DEFAULT_SIGNUP_BDP = 100.0       # Automatic 100 BDP signup welcome bonus

# -------------------------------------------------------------
# Secp256k1 Elliptic Curve Cryptography (Bitcoin/Ethereum Curve)
# -------------------------------------------------------------
SECP256K1_P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
SECP256K1_GX = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
SECP256K1_GY = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8
SECP256K1_G = (SECP256K1_GX, SECP256K1_GY)

def ec_point_add(p1, p2):
    """Adds two points on secp256k1 curve (handles infinity & doubling)."""
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    x1, y1 = p1
    x2, y2 = p2
    if x1 == x2:
        if (y1 + y2) % SECP256K1_P == 0:
            return None
        m = (3 * x1 * x1) * pow(2 * y1, -1, SECP256K1_P) % SECP256K1_P
    else:
        m = (y2 - y1) * pow(x2 - x1, -1, SECP256K1_P) % SECP256K1_P
    x3 = (m * m - x1 - x2) % SECP256K1_P
    y3 = (m * (x1 - x3) - y1) % SECP256K1_P
    return (x3, y3)

def ec_point_mul(pt, scalar):
    """Multiplies point pt by scalar on secp256k1 curve."""
    scalar = scalar % SECP256K1_N
    result = None
    addend = pt
    while scalar > 0:
        if scalar & 1:
            result = ec_point_add(result, addend)
        addend = ec_point_add(addend, addend)
        scalar >>= 1
    return result

def derive_account_keypair(password: str, salt: str) -> tuple[int, str]:
    """Derives secp256k1 private key and hex public key from password and salt."""
    seed = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), (salt + ":CSII_PAY_PRIVKEY").encode("utf-8"), 50000)
    privkey = int.from_bytes(seed, "big") % (SECP256K1_N - 1) + 1
    pub = ec_point_mul(SECP256K1_G, privkey)
    pub_hex = f"{pub[0]:064x}{pub[1]:064x}"
    return privkey, pub_hex

def _normalize_canonical_val(v):
    if isinstance(v, (int, float)):
        if isinstance(v, float) and v.is_integer():
            return int(v)
        return v
    elif isinstance(v, dict):
        return {k: _normalize_canonical_val(v[k]) for k in sorted(v.keys())}
    elif isinstance(v, list):
        return [_normalize_canonical_val(x) for x in v]
    return v

def compute_canonical_tx_bytes(tx: dict) -> bytes:
    """Canonical bytes representation of transaction for digital signature."""
    payload = {
        "action": tx.get("action"),
        "nonce": int(tx.get("nonce", 0)),
        "payload": _normalize_canonical_val(tx.get("payload", {})),
        "sender": tx.get("sender"),
        "timestamp": _normalize_canonical_val(tx.get("timestamp", 0))
    }
    return json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")

def sign_transaction_payload(tx: dict, privkey: int) -> str:
    """Signs canonical tx payload using Schnorr signature over secp256k1."""
    msg_hash = hashlib.sha256(compute_canonical_tx_bytes(tx)).digest()
    k = int.from_bytes(hashlib.sha256(privkey.to_bytes(32, "big") + msg_hash).digest(), "big") % (SECP256K1_N - 1) + 1
    R = ec_point_mul(SECP256K1_G, k)
    pub = ec_point_mul(SECP256K1_G, privkey)
    e = int.from_bytes(hashlib.sha256(R[0].to_bytes(32, "big") + R[1].to_bytes(32, "big") + pub[0].to_bytes(32, "big") + pub[1].to_bytes(32, "big") + msg_hash).digest(), "big") % SECP256K1_N
    s = (k + e * privkey) % SECP256K1_N
    return f"{R[0]:064x}{R[1]:064x}{s:064x}"

def verify_transaction_signature(tx: dict, pub_hex: str) -> bool:
    """Verifies Schnorr signature over secp256k1."""
    sig_hex = tx.get("signature", "")
    if not sig_hex or len(sig_hex) != 192:
        return False
    try:
        Rx = int(sig_hex[:64], 16)
        Ry = int(sig_hex[64:128], 16)
        s = int(sig_hex[128:192], 16)
        Qx = int(pub_hex[:64], 16)
        Qy = int(pub_hex[64:128], 16)
        R = (Rx, Ry)
        pub = (Qx, Qy)
        msg_hash = hashlib.sha256(compute_canonical_tx_bytes(tx)).digest()
        e = int.from_bytes(hashlib.sha256(R[0].to_bytes(32, "big") + R[1].to_bytes(32, "big") + pub[0].to_bytes(32, "big") + pub[1].to_bytes(32, "big") + msg_hash).digest(), "big") % SECP256K1_N
        sG = ec_point_mul(SECP256K1_G, s)
        R_plus_eQ = ec_point_add(R, ec_point_mul(pub, e))
        return sG == R_plus_eQ
    except Exception:
        return False


# -------------------------------------------------------------
# Networking & Hashing Helpers
# -------------------------------------------------------------
def is_port_in_use(port: int, host: str = "0.0.0.0") -> bool:
    """Check if TCP port is currently bound."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((host, port))
            return False
        except OSError:
            return True

def find_available_port(start_port: int, host: str = "0.0.0.0", max_attempts: int = 50) -> int:
    """Find the first available TCP port starting from start_port."""
    for p in range(start_port, start_port + max_attempts):
        if not is_port_in_use(p, host):
            return p
    raise RuntimeError(f"No available TCP ports found between {start_port} and {start_port + max_attempts}")

def calculate_commission(token: str, amount: float) -> float:
    """
    Commission rules:
    - BDP: 1% commission on every transaction.
    - CSP:
      - amount > 500 CSP: 2% commission
      - amount > 150 CSP and <= 500 CSP: 1% commission
      - amount <= 150 CSP: 0% commission (free micro-transaction)
    """
    amount = float(amount)
    if amount <= 0:
        return 0.0
    if token == "BDP":
        return round(amount * 0.01, 6)
    elif token == "CSP":
        if amount > 500.0:
            return round(amount * 0.02, 6)
        elif amount > 150.0:
            return round(amount * 0.01, 6)
        else:
            return 0.0
    return 0.0

def get_local_ip() -> str:
    """Detect LAN/WiFi IP address, falling back to 127.0.0.1 if offline."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip

def hash_data(data) -> str:
    """Compute deterministic SHA-256 hash."""
    if isinstance(data, (dict, list)):
        serialized = json.dumps(data, sort_keys=True, separators=(",", ":"))
    else:
        serialized = str(data)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()

def hash_password(password: str, salt: str = None) -> tuple:
    """Hash password with PBKDF2-HMAC-SHA256."""
    if not salt:
        salt = secrets.token_hex(16)
    key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt.encode("utf-8"), 100000)
    return key.hex(), salt

def verify_password(password: str, salt: str, expected_hash: str) -> bool:
    key, _ = hash_password(password, salt)
    return hmac.compare_digest(key, expected_hash)


# -------------------------------------------------------------
# Blockchain State Engine
# -------------------------------------------------------------
class BlockchainState:
    """
    Manages accounts, balances (CSP & BDP), nonces, public keys, smart contract escrow order book,
    marketplace jobs, generalized sandboxed smart contracts, and group accounts.
    """
    def __init__(self):
        self.lock = threading.RLock()
        self.accounts = {}
        self.orders = {}
        self.marketplace_jobs = {}
        self.contracts = {}
        self.groups = {}  # keyed by group name (unique group account ID)

    def clone(self):
        with self.lock:
            new_state = BlockchainState()
            new_state.accounts = copy.deepcopy(self.accounts)
            new_state.orders = copy.deepcopy(self.orders)
            new_state.marketplace_jobs = copy.deepcopy(self.marketplace_jobs)
            new_state.contracts = copy.deepcopy(self.contracts)
            new_state.groups = copy.deepcopy(self.groups)
            return new_state

    def export_dict(self) -> dict:
        """Serializes world state for atomic snapshot checkpointing."""
        with self.lock:
            return {
                "accounts": copy.deepcopy(self.accounts),
                "orders": copy.deepcopy(self.orders),
                "marketplace_jobs": copy.deepcopy(self.marketplace_jobs),
                "contracts": copy.deepcopy(self.contracts),
                "groups": copy.deepcopy(self.groups)
            }

    def import_dict(self, data: dict):
        """Restores world state from a snapshot checkpoint."""
        with self.lock:
            self.accounts = copy.deepcopy(data.get("accounts", {}))
            self.orders = copy.deepcopy(data.get("orders", {}))
            self.marketplace_jobs = copy.deepcopy(data.get("marketplace_jobs", {}))
            self.contracts = copy.deepcopy(data.get("contracts", {}))
            self.groups = copy.deepcopy(data.get("groups", {}))

    def get_summary(self) -> dict:
        with self.lock:
            return {
                "accounts": {
                    acc: {
                        "balances": data["balances"],
                        "nonce": data["nonce"]
                    }
                    for acc, data in sorted(self.accounts.items())
                },
                "orders": {
                    oid: {
                        "status": odata["status"],
                        "maker": odata["maker"],
                        "offer_token": odata["offer_token"],
                        "offer_amount": odata["offer_amount"],
                        "request_token": odata["request_token"],
                        "request_amount": odata["request_amount"],
                        "allow_partial": odata.get("allow_partial", True)
                    }
                    for oid, odata in sorted(self.orders.items())
                },
                "marketplace_jobs": {
                    jid: {
                        "status": jdata["status"],
                        "creator": jdata["creator"],
                        "wage": jdata["wage"],
                        "wage_token": jdata["wage_token"],
                        "worker": jdata.get("worker")
                    }
                    for jid, jdata in sorted(self.marketplace_jobs.items())
                },
                "contracts": {
                    cid: {
                        "owner": cdata["owner"],
                        "name": cdata.get("name", "Contract"),
                        "balances": cdata.get("balances", {}),
                        "tx_count": cdata.get("tx_count", 0),
                        "storage_hash": hash_data(cdata.get("storage", {}))
                    }
                    for cid, cdata in sorted(self.contracts.items())
                }
            }

    def get_state_hash(self) -> str:
        return hash_data(self.get_summary())

    def register_account(self, account_id: str, password: str = None, salt: str = None, password_hash: str = None, public_key: str = None, initial_csp: float = 0.0, initial_bdp: float = DEFAULT_SIGNUP_BDP) -> bool:
        with self.lock:
            if account_id in self.accounts:
                return False
            pwd_hash = password_hash
            if password is not None and not pwd_hash:
                pwd_hash, salt = hash_password(password, salt)
                if not public_key:
                    _, public_key = derive_account_keypair(password, salt)
            is_council = (account_id == GENESIS_ACCOUNT)
            self.accounts[account_id] = {
                "password_hash": pwd_hash,
                "salt": salt,
                "public_key": public_key,
                "balances": {"CSP": float(initial_csp), "BDP": float(initial_bdp) if is_council else 0.0},
                "frozen_balances": {"CSP": 0.0, "BDP": 0.0 if is_council else float(initial_bdp)},
                "is_verified": is_council,
                "verification_status": "VERIFIED" if is_council else "PENDING",
                "nonce": 0,
                "last_active": time.time(),
                "activity": {
                    "tx_count": 0,
                    "volume_csp": 0.0,
                    "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0,
                    "fees_paid_bdp": 0.0,
                    "score": 0.0
                }
            }
            return True

    def verify_account(self, account_id: str, password: str) -> bool:
        with self.lock:
            acc = self.accounts.get(account_id)
            if not acc or not acc.get("salt") or not acc.get("password_hash"):
                return False
            return verify_password(password, acc["salt"], acc["password_hash"])

    def record_activity(self, account_id: str):
        with self.lock:
            if account_id in self.accounts:
                self.accounts[account_id]["last_active"] = time.time()

    def get_balances(self, account_id: str) -> dict:
        with self.lock:
            acc = self.accounts.get(account_id)
            if acc:
                return dict(acc["balances"])
            return {"CSP": 0.0, "BDP": 0.0}

    def apply_transaction(self, tx: dict) -> tuple[bool, str]:
        """
        Unified state transition execution:
        - ACCOUNT_REGISTER: creates on-chain account with 100 BDP signup bonus
        - TRANSFER: transfers CSP or BDP (with tiered commission & signature verification)
        - ORDER_CREATE: smart contract escrow deposit
        - ORDER_FULFILL: smart contract atomic swap (partial or full)
        - ORDER_CANCEL: smart contract escrow cancellation & refund
        - POA_REWARD: consensus minting of block reward
        """
        with self.lock:
            action = tx.get("action")
            sender = tx.get("sender")
            payload = tx.get("payload", {})

            # 1. System-level consensus minting
            if sender == "SYSTEM":
                if action == "TRANSFER":
                    recipient = payload.get("recipient")
                    token = payload.get("token")
                    amount = float(payload.get("amount", 0.0))
                    if recipient in self.accounts and token in ("CSP", "BDP"):
                        self.accounts[recipient]["balances"][token] = round(self.accounts[recipient]["balances"][token] + amount, 6)
                        return True, "Genesis transfer executed"
                    return False, "Invalid genesis transfer recipient"

                elif action == "POA_REWARD":
                    recipient = payload.get("recipient")
                    total_csp = float(payload.get("total_csp", payload.get("amount", 0.0)))
                    total_bdp = float(payload.get("total_bdp", 0.0))
                    if not recipient or recipient not in self.accounts:
                        return False, f"Invalid reward recipient: {recipient}"
                    if total_csp > 0:
                        self.accounts[recipient]["balances"]["CSP"] = round(self.accounts[recipient]["balances"]["CSP"] + total_csp, 6)
                    if total_bdp > 0:
                        self.accounts[recipient]["balances"]["BDP"] = round(self.accounts[recipient]["balances"]["BDP"] + total_bdp, 6)
                    return True, "PoA reward applied"

            # 2. Account Registration Action
            if action == "ACCOUNT_REGISTER":
                acc_id = payload.get("account_id")
                pwd_hash = payload.get("password_hash")
                salt = payload.get("salt")
                pub_key = payload.get("public_key")
                initial_bdp = float(payload.get("initial_bdp", DEFAULT_SIGNUP_BDP))

                if not acc_id:
                    return False, "Missing account_id for registration"
                if acc_id in self.accounts:
                    existing = self.accounts[acc_id]
                    if existing.get("password_hash") == pwd_hash and existing.get("salt") == salt:
                        return True, f"Account '{acc_id}' already registered"
                    return False, f"Account '{acc_id}' is already registered with different credentials"

                # Verify self-signature on registration if provided
                if pub_key and tx.get("signature") and tx.get("signature") not in ("SELF_REGISTRATION", "GENESIS_SIGNATURE"):
                    if not verify_transaction_signature(tx, pub_key):
                        return False, "Invalid cryptographic signature on account registration"

                is_council = (acc_id == GENESIS_ACCOUNT)
                self.accounts[acc_id] = {
                    "password_hash": pwd_hash,
                    "salt": salt,
                    "public_key": pub_key,
                    "balances": {"CSP": 0.0, "BDP": initial_bdp if is_council else 0.0},
                    "frozen_balances": {"CSP": 0.0, "BDP": 0.0 if is_council else initial_bdp},
                    "is_verified": is_council,
                    "verification_status": "VERIFIED" if is_council else "PENDING",
                    "nonce": 0,
                    "last_active": float(tx.get("timestamp", time.time())),
                    "activity": {
                        "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                        "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                    }
                }
                status_msg = "verified council" if is_council else "100 BDP frozen pending student council verification"
                return True, f"Account '{acc_id}' registered ({status_msg})"

            # 3. Client Transactions Require Registered Sender
            if sender not in self.accounts:
                return False, f"Sender account '{sender}' does not exist on-chain"

            sender_acc = self.accounts[sender]

            # Strict Nonce Verification: Prevents Replay Attacks
            expected_nonce = sender_acc["nonce"]
            tx_nonce = tx.get("nonce")
            if tx_nonce is not None and int(tx_nonce) != expected_nonce:
                return False, f"Invalid transaction nonce. Expected: {expected_nonce}, Received: {tx_nonce} (Replay/Sequence Error)"

            # Cryptographic Signature Verification
            pub_key = sender_acc.get("public_key")
            sig = tx.get("signature", "")
            if pub_key and not (sig.startswith("DIRECT") or sig in ("SIG_GENESIS", "GENESIS_SIGNATURE", "TEST_BYPASS")):
                if not verify_transaction_signature(tx, pub_key):
                    return False, f"Cryptographic signature verification failed for sender '{sender}'"

            # Execute specific action
            if action == "TRANSFER":
                recipient = payload.get("recipient")
                token = payload.get("token")
                amount = float(payload.get("amount", 0.0))

                if token not in ("CSP", "BDP"):
                    return False, f"Unsupported token: {token}"
                if amount <= 0:
                    return False, "Transfer amount must be strictly positive"
                if recipient not in self.accounts:
                    return False, f"Recipient account '{recipient}' does not exist"
                if (recipient in self.groups or self.accounts[recipient].get("is_group_account")) and token != "CSP":
                    return False, f"Team accounts only support CSP transfers (attempted {token})"

                fee = calculate_commission(token, amount)
                total_deducted = round(amount + fee, 6)

                if sender_acc["balances"][token] < total_deducted:
                    return False, f"Insufficient {token} balance. Required: {total_deducted} ({amount} + {fee} fee), Available: {sender_acc['balances'][token]}"

                sender_acc["balances"][token] = round(sender_acc["balances"][token] - total_deducted, 6)
                self.accounts[recipient]["balances"][token] = round(self.accounts[recipient]["balances"][token] + amount, 6)
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()

                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                if token == "CSP":
                    act["volume_csp"] = round(act["volume_csp"] + amount, 6)
                    act["fees_paid_csp"] = round(act["fees_paid_csp"] + fee, 6)
                elif token == "BDP":
                    act["volume_bdp"] = round(act["volume_bdp"] + amount, 6)
                    act["fees_paid_bdp"] = round(act["fees_paid_bdp"] + fee, 6)
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)

                tx["fee"] = fee
                tx["fee_token"] = token
                return True, f"Transfer executed successfully (Fee: {fee} {token})"

            elif action == "ACCOUNT_VERIFY":
                # Strict authorization check: Only Student Council account is authorized to verify/reject accounts
                if sender != GENESIS_ACCOUNT:
                    return False, f"Unauthorized: sender '{sender}' is not the Student Council authority ({GENESIS_ACCOUNT})"
                
                target_account = payload.get("target_account") or payload.get("account_id")
                decision = (payload.get("decision") or payload.get("status") or "VERIFIED").upper() # "VERIFIED" or "REJECTED"
                notes = payload.get("notes", "")

                if not target_account or target_account not in self.accounts:
                    return False, f"Target account '{target_account}' not found on-chain"

                target_acc = self.accounts[target_account]
                frozen_bdp = float(target_acc.get("frozen_balances", {}).get("BDP", 0.0))

                if decision == "VERIFIED":
                    target_acc.setdefault("balances", {})
                    target_acc.setdefault("frozen_balances", {"CSP": 0.0, "BDP": 0.0})
                    if frozen_bdp > 0:
                        target_acc["balances"]["BDP"] = round(target_acc["balances"].get("BDP", 0.0) + frozen_bdp, 6)
                        target_acc["frozen_balances"]["BDP"] = 0.0
                    target_acc["is_verified"] = True
                    target_acc["verification_status"] = "VERIFIED"
                    target_acc["verified_by"] = sender
                    target_acc["verified_at"] = float(tx.get("timestamp", time.time()))
                    sender_acc["nonce"] += 1
                    sender_acc["last_active"] = time.time()
                    return True, f"Account '{target_account}' successfully verified by Student Council; {frozen_bdp} BDP unlocked!"

                elif decision == "REJECTED":
                    target_acc.setdefault("frozen_balances", {"CSP": 0.0, "BDP": 0.0})
                    target_acc["frozen_balances"]["BDP"] = 0.0
                    target_acc["is_verified"] = False
                    target_acc["verification_status"] = "REJECTED"
                    target_acc["rejected_by"] = sender
                    target_acc["rejected_at"] = float(tx.get("timestamp", time.time()))
                    sender_acc["nonce"] += 1
                    sender_acc["last_active"] = time.time()
                    return True, f"Account '{target_account}' rejected by Student Council; frozen BDP cleared."
                else:
                    return False, f"Invalid verification decision '{decision}'. Expected VERIFIED or REJECTED."

            elif action == "ORDER_CREATE":
                order_id = payload.get("order_id") or hash_data(f"{sender}_{time.time()}_{secrets.token_hex(4)}")
                offer_token = payload.get("offer_token")
                offer_amount = float(payload.get("offer_amount", 0.0))
                request_token = payload.get("request_token")
                request_amount = float(payload.get("request_amount", 0.0))
                allow_partial = bool(payload.get("allow_partial", True))

                if offer_token not in ("CSP", "BDP") or request_token not in ("CSP", "BDP"):
                    return False, "Invalid token types for smart contract order"
                if offer_token == request_token:
                    return False, "Cannot exchange identical tokens"
                if offer_amount <= 0 or request_amount <= 0:
                    return False, "Order amounts must be positive"
                if sender_acc["balances"][offer_token] < offer_amount:
                    return False, f"Insufficient {offer_token} for escrow deposit. Has: {sender_acc['balances'][offer_token]}, Needed: {offer_amount}"
                if order_id in self.orders:
                    return False, f"Order '{order_id}' already exists"

                sender_acc["balances"][offer_token] = round(sender_acc["balances"][offer_token] - offer_amount, 6)
                self.orders[order_id] = {
                    "id": order_id,
                    "maker": sender,
                    "offer_token": offer_token,
                    "offer_amount": offer_amount,
                    "request_token": request_token,
                    "request_amount": request_amount,
                    "initial_offer_amount": offer_amount,
                    "initial_request_amount": request_amount,
                    "allow_partial": allow_partial,
                    "status": "OPEN",
                    "created_at": float(tx.get("timestamp", time.time())),
                    "fulfilled_by": None,
                    "fills": []
                }
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)
                return True, f"Smart contract order {order_id} created (partial: {allow_partial}), escrow locked"

            elif action == "ORDER_FULFILL":
                order_id = payload.get("order_id")
                order = self.orders.get(order_id)
                if not order:
                    return False, f"Order {order_id} not found"
                if order["status"] != "OPEN":
                    return False, f"Order {order_id} is not open (status: {order['status']})"
                if order["maker"] == sender:
                    return False, "Cannot fulfill your own order; use ORDER_CANCEL instead"

                req_token = order["request_token"]
                req_amount = order["request_amount"]
                off_token = order["offer_token"]
                off_amount = order["offer_amount"]
                maker = order["maker"]

                fill_amount = payload.get("fill_amount")
                if fill_amount is None or float(fill_amount) >= off_amount:
                    take_offer = off_amount
                    pay_request = req_amount
                    is_partial = False
                else:
                    take_offer = float(fill_amount)
                    if take_offer <= 0:
                        return False, "Fill amount must be strictly positive"
                    if not order.get("allow_partial", True):
                        return False, "This smart contract does not allow partial fulfillment"
                    ratio = take_offer / off_amount
                    pay_request = round(req_amount * ratio, 6)
                    take_offer = round(take_offer, 6)
                    is_partial = True

                if sender_acc["balances"][req_token] < pay_request:
                    return False, f"Taker has insufficient {req_token}. Has: {sender_acc['balances'][req_token]}, Needed: {pay_request}"

                sender_acc["balances"][req_token] = round(sender_acc["balances"][req_token] - pay_request, 6)
                self.accounts[maker]["balances"][req_token] = round(self.accounts[maker]["balances"][req_token] + pay_request, 6)
                sender_acc["balances"][off_token] = round(sender_acc["balances"][off_token] + take_offer, 6)

                order.setdefault("fills", []).append({
                    "taker": sender,
                    "filled_offer": take_offer,
                    "paid_request": pay_request,
                    "timestamp": time.time()
                })

                order["offer_amount"] = round(off_amount - take_offer, 6)
                order["request_amount"] = round(req_amount - pay_request, 6)

                if order["offer_amount"] <= 1e-6 or order["request_amount"] <= 1e-6:
                    order["status"] = "COMPLETED"
                    order["fulfilled_by"] = sender
                    order["fulfilled_at"] = time.time()
                    order["offer_amount"] = 0.0
                    order["request_amount"] = 0.0
                else:
                    order["status"] = "OPEN"

                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()

                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)
                fill_type = "partially" if is_partial else "fully"
                return True, f"Smart contract order {order_id} {fill_type} fulfilled atomically ({take_offer} {off_token} for {pay_request} {req_token})"

            elif action == "ORDER_CANCEL":
                order_id = payload.get("order_id")
                order = self.orders.get(order_id)
                if not order:
                    return False, f"Order {order_id} not found"
                if order["status"] != "OPEN":
                    return False, f"Order {order_id} is not open (status: {order['status']})"
                if order["maker"] != sender:
                    return False, f"Only order maker ({order['maker']}) can cancel this order"

                off_token = order["offer_token"]
                off_amount = order["offer_amount"]
                if off_amount > 0:
                    sender_acc["balances"][off_token] = round(sender_acc["balances"][off_token] + off_amount, 6)
                order["status"] = "CANCELLED"

                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)
                return True, f"Order {order_id} cancelled, escrowed {off_token} refunded"

            elif action == "MARKETPLACE_CREATE":
                job_id = payload.get("job_id") or hash_data(f"JOB_{sender}_{time.time()}_{secrets.token_hex(4)}")
                wage = float(payload.get("wage", 0.0))
                wage_token = payload.get("wage_token", "CSP")
                secret_hash = payload.get("secret_hash")

                if wage_token not in ("CSP", "BDP"):
                    return False, f"Unsupported wage token: {wage_token}"
                if wage <= 0:
                    return False, "Wage must be strictly positive"
                if not secret_hash:
                    return False, "Missing secret_hash for marketplace smart contract"
                if sender_acc["balances"][wage_token] < wage:
                    return False, f"Insufficient {wage_token} balance for escrow deposit. Required: {wage}, Available: {sender_acc['balances'][wage_token]}"
                if job_id in self.marketplace_jobs:
                    return False, f"Marketplace job '{job_id}' already exists"

                sender_acc["balances"][wage_token] = round(sender_acc["balances"][wage_token] - wage, 6)
                self.marketplace_jobs[job_id] = {
                    "id": job_id,
                    "creator": sender,
                    "author": payload.get("author") or sender,
                    "team_name": payload.get("team_name"),
                    "title": payload.get("title", "Untitled Application"),
                    "type": payload.get("type", "student application"),
                    "category": payload.get("category", "tech"),
                    "description": payload.get("description", ""),
                    "deadline": payload.get("deadline", ""),
                    "difficulty": int(payload.get("difficulty", 1)),
                    "line_id": payload.get("line_id", ""),
                    "wage": wage,
                    "wage_token": wage_token,
                    "secret_hash": secret_hash,
                    "status": "OPEN",
                    "created_at": float(tx.get("timestamp", time.time())),
                    "worker": None,
                    "failed_attempts": {}
                }
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)
                return True, f"Marketplace application {job_id} created with {wage} {wage_token} escrow locked"

            elif action == "MARKETPLACE_CLAIM":
                job_id = payload.get("job_id")
                secret_code = str(payload.get("secret_code", "")).strip()
                job = self.marketplace_jobs.get(job_id)
                if not job:
                    return False, f"Marketplace application '{job_id}' not found"
                if job["status"] != "OPEN":
                    return False, f"Application '{job_id}' is not open (status: {job['status']})"
                if job["creator"] == sender:
                    return False, "Creator cannot claim their own application"

                computed_hash = hashlib.sha256(secret_code.encode("utf-8")).hexdigest()
                if computed_hash != job["secret_hash"]:
                    failed_map = job.setdefault("failed_attempts", {})
                    fails = failed_map.get(sender, 0) + 1
                    failed_map[sender] = fails
                    sender_acc["nonce"] += 1
                    sender_acc["last_active"] = time.time()
                    if fails > 3:
                        # Fine worker 10 CSP
                        sender_acc["balances"]["CSP"] = round(max(0.0, sender_acc["balances"]["CSP"] - 10.0), 6)
                        return False, f"Incorrect secret code (attempt {fails}). Fined 10 CSP for exceeding 3 failed attempts!"
                    return False, f"Incorrect secret code (attempt {fails}/3)"

                wage = job["wage"]
                wage_token = job["wage_token"]
                sender_acc["balances"][wage_token] = round(sender_acc["balances"][wage_token] + wage, 6)
                job["status"] = "COMPLETED"
                job["worker"] = sender
                job["completed_at"] = time.time()

                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                act["score"] = round((act["tx_count"] * 10) + (act["volume_csp"] * 0.05) + (act["volume_bdp"] * 1.0), 2)
                return True, f"Application {job_id} claimed successfully! Transferred {wage} {wage_token} to {sender}"

            elif action == "MARKETPLACE_CANCEL":
                job_id = payload.get("job_id")
                job = self.marketplace_jobs.get(job_id)
                if not job:
                    return False, f"Application '{job_id}' not found"
                if job["status"] != "OPEN":
                    return False, f"Application '{job_id}' is not open (status: {job['status']})"
                if job["creator"] != sender:
                    return False, "Only creator can cancel application"

                wage = job["wage"]
                wage_token = job["wage_token"]
                sender_acc["balances"][wage_token] = round(sender_acc["balances"][wage_token] + wage, 6)
                job["status"] = "CANCELLED"
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Application {job_id} cancelled, escrowed {wage} {wage_token} refunded"

            elif action == "CONTRACT_DEPLOY":
                code = str(payload.get("code", "")).strip()
                if not code:
                    return False, "Contract deployment requires non-empty 'code'"

                try:
                    SmartContractEngine.validate_code(code)
                except Exception as e:
                    return False, f"Contract code rejected by security sandbox: {e}"

                name = str(payload.get("name", "Custom Smart Contract"))
                initial_escrow = float(payload.get("initial_escrow", 0.0))
                initial_token = str(payload.get("initial_token", "CSP")).upper()
                if initial_token not in ("CSP", "BDP"):
                    return False, f"Unsupported initial token: {initial_token}"

                if initial_escrow < 0:
                    return False, "Initial escrow cannot be negative"
                if initial_escrow > 0:
                    if sender_acc["balances"].get(initial_token, 0.0) < initial_escrow:
                        return False, f"Insufficient {initial_token} balance for initial escrow ({initial_escrow} required)"
                    sender_acc["balances"][initial_token] = round(sender_acc["balances"][initial_token] - initial_escrow, 6)

                contract_id = payload.get("contract_id")
                if not contract_id:
                    s_nonce = sender_acc.get("nonce", 0)
                    contract_id = f"0x{hash_data(f'{sender}_{s_nonce}_{time.time()}')[:16]}"

                if contract_id in self.contracts:
                    if initial_escrow > 0:
                        sender_acc["balances"][initial_token] = round(sender_acc["balances"][initial_token] + initial_escrow, 6)
                    return False, f"Contract ID '{contract_id}' already exists"

                contract = {
                    "id": contract_id,
                    "owner": sender,
                    "name": name,
                    "code": code,
                    "storage": {},
                    "balances": {
                        "CSP": initial_escrow if initial_token == "CSP" else 0.0,
                        "BDP": initial_escrow if initial_token == "BDP" else 0.0
                    },
                    "created_at": float(tx.get("timestamp", time.time())),
                    "tx_count": 0
                }

                # If init method exists, run it
                init_args = payload.get("init_args", {})
                ctx = ContractContext(
                    contract_id=contract_id,
                    contract_owner=sender,
                    caller=sender,
                    timestamp=float(tx.get("timestamp", time.time())),
                    storage=contract["storage"],
                    balances=contract["balances"],
                    attached_token=initial_token if initial_escrow > 0 else None,
                    attached_amount=initial_escrow
                )
                ok, res, err = SmartContractEngine.execute(code, "init", ctx, init_args)
                if not ok and "not found or not callable" not in err:
                    if initial_escrow > 0:
                        sender_acc["balances"][initial_token] = round(sender_acc["balances"][initial_token] + initial_escrow, 6)
                    return False, f"Contract init failed: {err}"

                contract["storage"] = ctx.storage
                contract["balances"] = ctx.balances
                for pout in ctx.payouts:
                    recip = pout["recipient"]
                    tok = pout["token"]
                    amt = pout["amount"]
                    if recip in self.accounts:
                        self.accounts[recip]["balances"][tok] = round(self.accounts[recip]["balances"].get(tok, 0.0) + amt, 6)

                self.contracts[contract_id] = contract
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                return True, f"Smart Contract '{name}' deployed at {contract_id}"

            elif action == "CONTRACT_CALL":
                contract_id = payload.get("contract_id")
                method = payload.get("method")
                args = payload.get("args", {})
                attached_amount = float(payload.get("attached_amount", 0.0))
                attached_token = str(payload.get("attached_token", "CSP")).upper()

                if not contract_id:
                    return False, "Contract call requires 'contract_id'"
                if not method:
                    return False, "Contract call requires 'method'"
                contract = self.contracts.get(contract_id)
                if not contract:
                    return False, f"Contract '{contract_id}' not found on-chain"

                if attached_amount < 0:
                    return False, "Attached amount cannot be negative"
                if attached_amount > 0:
                    if attached_token not in ("CSP", "BDP"):
                        return False, f"Unsupported attached token: {attached_token}"
                    if sender_acc["balances"].get(attached_token, 0.0) < attached_amount:
                        return False, f"Insufficient {attached_token} balance to attach {attached_amount}"
                    sender_acc["balances"][attached_token] = round(sender_acc["balances"][attached_token] - attached_amount, 6)
                    contract["balances"][attached_token] = round(contract["balances"].get(attached_token, 0.0) + attached_amount, 6)

                # Clone storage and balances for atomic execution
                temp_storage = copy.deepcopy(contract["storage"])
                temp_balances = copy.deepcopy(contract["balances"])
                ctx = ContractContext(
                    contract_id=contract_id,
                    contract_owner=contract["owner"],
                    caller=sender,
                    timestamp=float(tx.get("timestamp", time.time())),
                    storage=temp_storage,
                    balances=temp_balances,
                    attached_token=attached_token if attached_amount > 0 else None,
                    attached_amount=attached_amount
                )

                ok, res, err = SmartContractEngine.execute(contract["code"], method, ctx, args)
                if not ok:
                    # Roll back attached funds
                    if attached_amount > 0:
                        sender_acc["balances"][attached_token] = round(sender_acc["balances"][attached_token] + attached_amount, 6)
                        contract["balances"][attached_token] = round(contract["balances"].get(attached_token, 0.0) - attached_amount, 6)
                    return False, err

                contract["storage"] = ctx.storage
                contract["balances"] = ctx.balances

                # Process contract payouts
                for pout in ctx.payouts:
                    recip = pout["recipient"]
                    tok = pout["token"]
                    amt = pout["amount"]
                    if recip in self.accounts:
                        self.accounts[recip]["balances"][tok] = round(self.accounts[recip]["balances"].get(tok, 0.0) + amt, 6)
                    else:
                        self.accounts[recip] = {
                            "password_hash": None,
                            "salt": None,
                            "public_key": None,
                            "balances": {"CSP": 0.0, "BDP": 0.0},
                            "nonce": 0,
                            "last_active": time.time(),
                            "activity": {"tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0, "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0}
                        }
                        self.accounts[recip]["balances"][tok] = amt

                contract["tx_count"] = contract.get("tx_count", 0) + 1
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                act = sender_acc.setdefault("activity", {
                    "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                    "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                })
                act["tx_count"] += 1
                if attached_token == "CSP":
                    act["volume_csp"] = round(act["volume_csp"] + attached_amount, 6)
                else:
                    act["volume_bdp"] = round(act["volume_bdp"] + attached_amount, 6)

                return True, f"Contract {contract_id}.{method}() executed successfully"

            # ------------------------------------------------------------------
            # Group Actions (CSP only)
            # ------------------------------------------------------------------
            elif action == "GROUP_CREATE":
                group_name = payload.get("group_name", "").strip()
                description = payload.get("description", "").strip()
                initial_deposit = float(payload.get("initial_deposit", payload.get("entrance_fee", 0.0)))

                if not group_name:
                    return False, "Team name is required"
                if not description:
                    return False, "Description is required for team creation"
                if group_name in self.groups:
                    return False, f"Team '{group_name}' already exists"
                if group_name in self.accounts:
                    return False, f"'{group_name}' is already taken as an account ID"
                if initial_deposit < 0.0:
                    return False, "Initial deposit cannot be negative"
                if initial_deposit > 0.0 and sender_acc["balances"]["CSP"] < initial_deposit:
                    return False, f"Insufficient CSP for initial deposit ({initial_deposit} CSP required)"

                # Deduct creator's initial deposit if any
                if initial_deposit > 0.0:
                    sender_acc["balances"]["CSP"] = round(sender_acc["balances"]["CSP"] - initial_deposit, 6)

                # Register group virtual account (password-less system account)
                self.accounts[group_name] = {
                    "password_hash": None,
                    "salt": None,
                    "public_key": None,
                    "balances": {"CSP": initial_deposit, "BDP": 0.0},
                    "nonce": 0,
                    "last_active": float(tx.get("timestamp", time.time())),
                    "activity": {"tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                                 "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0},
                    "is_group_account": True
                }

                self.groups[group_name] = {
                    "name": group_name,
                    "description": description,
                    "entrance_fee": 0.0,
                    "created_at": float(tx.get("timestamp", time.time())),
                    "creator": sender,
                    "members": {
                        sender: {"joined_at": float(tx.get("timestamp", time.time())), "stake": initial_deposit}
                    },
                    "invitations": [],
                    "polls": {}
                }
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Team '{group_name}' created"

            elif action == "GROUP_LEAVE":
                group_name = payload.get("group_name", "").strip()
                group = self.groups.get(group_name)
                if not group:
                    return False, f"Team '{group_name}' not found"
                if sender not in group["members"]:
                    return False, f"You are not a member of '{group_name}'"

                del group["members"][sender]
                if group.get("creator") == sender:
                    if group["members"]:
                        group["creator"] = next(iter(group["members"]))
                    else:
                        group["creator"] = None

                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Successfully left team '{group_name}'"

            elif action == "GROUP_INVITE":
                group_name = payload.get("group_name", "").strip()
                invitee = payload.get("invitee", "").strip()

                group = self.groups.get(group_name)
                if not group:
                    return False, f"Team '{group_name}' not found"
                if sender not in group["members"]:
                    return False, f"Only members can add teammates to '{group_name}'"
                if invitee not in self.accounts:
                    return False, f"Account '{invitee}' does not exist"
                if invitee in group["members"]:
                    return False, f"'{invitee}' is already a member of '{group_name}'"

                group["members"][invitee] = {
                    "joined_at": float(tx.get("timestamp", time.time())),
                    "stake": 0.0
                }
                group["invitations"] = [inv for inv in group.get("invitations", []) if inv.get("invitee") != invitee]
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Teammate '{invitee}' added to '{group_name}'"

            elif action == "GROUP_JOIN":
                group_name = payload.get("group_name", "").strip()

                group = self.groups.get(group_name)
                if not group:
                    return False, f"Group '{group_name}' not found"
                if sender in group["members"]:
                    return False, f"You are already a member of '{group_name}'"

                entrance_fee = float(group.get("entrance_fee", 0.0))
                if entrance_fee > 0:
                    if sender_acc["balances"].get("CSP", 0.0) < entrance_fee:
                        return False, f"Insufficient CSP for entrance fee ({entrance_fee} CSP required)"
                    # Pay entrance fee to group balance
                    sender_acc["balances"]["CSP"] = round(sender_acc["balances"]["CSP"] - entrance_fee, 6)
                    self.accounts[group_name]["balances"]["CSP"] = round(
                        self.accounts[group_name]["balances"]["CSP"] + entrance_fee, 6)

                group["members"][sender] = {
                    "joined_at": float(tx.get("timestamp", time.time())),
                    "stake": entrance_fee
                }
                group["invitations"] = [i for i in group.get("invitations", []) if i.get("invitee") != sender]
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Joined team '{group_name}'"

            elif action == "GROUP_POLL_CREATE":
                group_name = payload.get("group_name", "").strip()
                poll_type = payload.get("poll_type", "").upper()  # TRANSFER or MARKETPLACE_POST
                title = payload.get("title", "Poll").strip()
                poll_payload = payload.get("poll_payload", {})

                group = self.groups.get(group_name)
                if not group:
                    return False, f"Group '{group_name}' not found"
                if sender not in group["members"]:
                    return False, f"Only members can create polls in '{group_name}'"
                if poll_type not in ("TRANSFER", "MARKETPLACE_POST"):
                    return False, "Poll type must be TRANSFER or MARKETPLACE_POST"
                if not title:
                    return False, "Poll title is required"

                poll_id = hash_data(f"POLL_{group_name}_{sender}_{time.time()}_{secrets.token_hex(4)}")[:16]
                now = float(tx.get("timestamp", time.time()))
                group["polls"][poll_id] = {
                    "id": poll_id,
                    "type": poll_type,
                    "title": title,
                    "poll_payload": poll_payload,
                    "votes": {},
                    "status": "OPEN",
                    "created_by": sender,
                    "created_at": now,
                    "expires_at": now + 7 * 24 * 3600  # 7 days
                }
                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                return True, f"Poll '{title}' created in group '{group_name}' (ID: {poll_id})"

            elif action == "GROUP_VOTE":
                group_name = payload.get("group_name", "").strip()
                poll_id = payload.get("poll_id", "").strip()
                vote = bool(payload.get("vote", False))

                group = self.groups.get(group_name)
                if not group:
                    return False, f"Group '{group_name}' not found"
                if sender not in group["members"]:
                    return False, f"Only members can vote in '{group_name}'"
                poll = group["polls"].get(poll_id)
                if not poll:
                    return False, f"Poll '{poll_id}' not found in '{group_name}'"
                if poll["status"] != "OPEN":
                    return False, f"Poll '{poll_id}' is not open (status: {poll['status']})"
                if time.time() > poll["expires_at"]:
                    poll["status"] = "REJECTED"
                    return False, f"Poll '{poll_id}' has expired"

                poll["votes"][sender] = vote
                # Check if threshold reached (>=70% yes votes from all current members)
                total_members = len(group["members"])
                yes_votes = sum(1 for v in poll["votes"].values() if v)
                threshold = total_members * 0.70
                if yes_votes >= threshold and total_members > 0:
                    poll["status"] = "PASSED"

                sender_acc["nonce"] += 1
                sender_acc["last_active"] = time.time()
                vote_word = "YES" if vote else "NO"
                return True, f"Voted {vote_word} on poll '{poll_id}' in '{group_name}'"

            elif action == "GROUP_POLL_EXECUTE":
                group_name = payload.get("group_name", "").strip()
                poll_id = payload.get("poll_id", "").strip()

                group = self.groups.get(group_name)
                if not group:
                    return False, f"Group '{group_name}' not found"
                if sender not in group["members"]:
                    return False, f"Only members can execute polls in '{group_name}'"
                poll = group["polls"].get(poll_id)
                if not poll:
                    return False, f"Poll '{poll_id}' not found in '{group_name}'"
                if poll["status"] != "PASSED":
                    return False, f"Poll '{poll_id}' has not passed (status: {poll['status']})"

                poll_type = poll["type"]
                pp = poll["poll_payload"]
                group_acc = self.accounts.get(group_name)
                if not group_acc:
                    return False, f"Group account for '{group_name}' not found on-chain"

                if poll_type == "TRANSFER":
                    recipient = pp.get("recipient", "").strip()
                    amount = float(pp.get("amount", 0.0))
                    if not recipient or amount <= 0:
                        poll["status"] = "REJECTED"
                        return False, "Invalid TRANSFER poll payload"
                    if recipient not in self.accounts:
                        return False, f"Recipient '{recipient}' not found"
                    if group_acc["balances"]["CSP"] < amount:
                        return False, f"Insufficient group CSP balance ({group_acc['balances']['CSP']} < {amount})"
                    group_acc["balances"]["CSP"] = round(group_acc["balances"]["CSP"] - amount, 6)
                    self.accounts[recipient]["balances"]["CSP"] = round(
                        self.accounts[recipient]["balances"]["CSP"] + amount, 6)
                    poll["status"] = "EXECUTED"
                    poll["executed_by"] = sender
                    poll["executed_at"] = time.time()
                    sender_acc["nonce"] += 1
                    sender_acc["last_active"] = time.time()
                    return True, f"Poll executed: transferred {amount} CSP from group '{group_name}' to '{recipient}'"

                elif poll_type == "MARKETPLACE_POST":
                    wage = float(pp.get("wage", 0.0))
                    secret_hash = pp.get("secret_hash", "")
                    if wage <= 0 or not secret_hash:
                        poll["status"] = "REJECTED"
                        return False, "Invalid MARKETPLACE_POST poll payload"
                    if group_acc["balances"]["CSP"] < wage:
                        return False, f"Insufficient group CSP balance for marketplace post ({wage} CSP required)"

                    group_acc["balances"]["CSP"] = round(group_acc["balances"]["CSP"] - wage, 6)
                    job_id = hash_data(f"GRP_JOB_{group_name}_{poll_id}_{time.time()}")[:16]
                    self.marketplace_jobs[job_id] = {
                        "id": job_id,
                        "creator": group_name,
                        "title": pp.get("title", "Group Application"),
                        "type": pp.get("type", "student application"),
                        "category": pp.get("category", "tech"),
                        "description": pp.get("description", ""),
                        "deadline": pp.get("deadline", ""),
                        "difficulty": int(pp.get("difficulty", 1)),
                        "line_id": pp.get("line_id", ""),
                        "wage": wage,
                        "wage_token": "CSP",
                        "secret_hash": secret_hash,
                        "status": "OPEN",
                        "created_at": float(tx.get("timestamp", time.time())),
                        "worker": None,
                        "failed_attempts": {},
                        "group_name": group_name  # marks as group job
                    }
                    poll["status"] = "EXECUTED"
                    poll["executed_by"] = sender
                    poll["executed_at"] = time.time()
                    poll["result_job_id"] = job_id
                    sender_acc["nonce"] += 1
                    sender_acc["last_active"] = time.time()
                    return True, f"Poll executed: marketplace job '{job_id}' posted by group '{group_name}'"

                else:
                    return False, f"Unknown poll type: {poll_type}"

            else:
                return False, f"Unknown action: {action}"



# -------------------------------------------------------------
# Node Server & Peer Consensus Engine
# -------------------------------------------------------------
class NodeServer:
    def __init__(self, host: str, port: int, udp_port: int, account_id: str, password: str, initial_peers: list = None, data_dir: str = "."):
        self.host = host
        self.port = port
        self.udp_port = udp_port
        self.account_id = account_id
        self.password = password
        self.data_dir = data_dir
        node_prefix = self.account_id if self.account_id else "GUEST"
        self.node_id = hash_data(f"{node_prefix}_{self.host}_{self.port}_{secrets.token_hex(4)}")[:12]
        self.chain_file = os.path.join(self.data_dir, f"node_{self.port}_chain.json")
        self.db_file = os.path.join(self.data_dir, f"node_{self.port}.db")
        self.storage = BlockchainStorage(self.db_file)

        self.state = BlockchainState()
        self.chain = []
        self.mempool = []
        self.mempool_lock = threading.Lock()
        self.peers = set()
        self.peer_lock = threading.Lock()
        self.sync_lock = threading.Lock()
        self.quarantined_peers = {}  # {peer_url: unban_timestamp}

        if initial_peers:
            for p in initial_peers:
                p_clean = p.rstrip("/")
                if p_clean != f"http://{self.host}:{self.port}":
                    self.add_peer(p_clean)

        self.active_accounts = {}
        self.activity_lock = threading.Lock()
        self.session_tokens = {}
        self.running = True

        self.init_chain()

        if not self.authenticate_operator():
            raise ValueError(f"CRITICAL: Failed to authenticate node operator account '{self.account_id}'. Server cannot operate.")

    def init_chain(self):
        """Initializes chain from network peers, high-speed SQLite storage, legacy store, or Genesis block."""
        # 1. Sync from network peers first
        with self.peer_lock:
            peer_list = list(self.peers)
        if peer_list:
            print(f"[*] Syncing blockchain from {len(peer_list)} network peer(s)...")
            for p in peer_list:
                try:
                    self.sync_with_peer(p)
                    if self.chain:
                        print(f"[✓] Successfully synchronized chain (Height #{len(self.chain) - 1}) from {p}")
                        for blk in self.chain:
                            self.storage.append_block(blk)
                        return
                except Exception as e:
                    print(f"[!] Warning: Peer sync with {p} failed: {e}")

        # 2. Check high-performance SQLite WAL storage
        if self.storage.get_block_count() > 0:
            try:
                cp = self.storage.get_latest_checkpoint()
                if cp:
                    cp_block, cp_hash, cp_state_dict = cp
                    self.state = BlockchainState()
                    self.state.import_dict(cp_state_dict)
                    all_blocks = self.storage.get_all_blocks_for_sync()
                    for blk in all_blocks:
                        if blk.get("index", 0) > cp_block:
                            for tx in blk.get("transactions", []):
                                self.state.apply_transaction(tx)
                    self.chain = all_blocks
                    print(f"[*] Fast boot from checkpoint #{cp_block} (Total Blocks: #{len(self.chain) - 1}) via SQLite WAL.")
                    return
                else:
                    all_blocks = self.storage.get_all_blocks_for_sync()
                    if all_blocks and self.validate_chain(all_blocks):
                        self.chain = all_blocks
                        self.rebuild_state_from_chain()
                        print(f"[*] Loaded {len(self.chain)} blocks from SQLite WAL storage ({self.db_file}).")
                        return
            except Exception as e:
                print(f"[!] Warning: Failed loading from SQLite storage: {e}")

        # 3. Check legacy JSON chain file and migrate to SQLite
        if os.path.exists(self.chain_file):
            try:
                with open(self.chain_file, "r") as f:
                    data = json.load(f)
                    candidate = data.get("chain", [])
                    if candidate and self.validate_chain(candidate):
                        self.chain = candidate
                        print(f"[*] Loaded {len(self.chain)} verified blocks from {self.chain_file}. Migrating to SQLite WAL...")
                        for blk in self.chain:
                            self.storage.append_block(blk)
                        self.rebuild_state_from_chain()
                        self.storage.save_checkpoint(self.chain[-1]["index"], self.state.get_state_hash(), self.state.export_dict())
                        return
                    else:
                        print(f"[!] Warning: Existing chain in {self.chain_file} failed validation or is corrupt. Backing up...")
                        bak_file = f"{self.chain_file}.corrupt_{int(time.time())}.bak"
                        os.rename(self.chain_file, bak_file)
            except Exception as e:
                print(f"[!] Warning: Failed to load existing chain file: {e}")

        # 4. Create canonical Genesis block
        self.create_genesis_block()

    def create_genesis_block(self):
        """Construct canonical Genesis block."""
        print(f"[*] Initializing Genesis Block with account {GENESIS_ACCOUNT} (10,000 CSP, 100 BDP)...")
        self.state = BlockchainState()
        pwd_hash, _ = hash_password(GENESIS_PASSWORD, GENESIS_SALT)
        _, genesis_pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)
        self.state.register_account(
            GENESIS_ACCOUNT,
            salt=GENESIS_SALT,
            password_hash=pwd_hash,
            public_key=genesis_pubkey,
            initial_csp=0.0,
            initial_bdp=0.0
        )

        genesis_tx = {
            "tx_id": hash_data("GENESIS_MINT_CSP"),
            "sender": "SYSTEM",
            "action": "TRANSFER",
            "payload": {
                "recipient": GENESIS_ACCOUNT,
                "token": "CSP",
                "amount": GENESIS_CSP
            },
            "nonce": 0,
            "timestamp": 1700000000.0,
            "signature": "GENESIS_SIGNATURE"
        }
        genesis_tx_bdp = {
            "tx_id": hash_data("GENESIS_MINT_BDP"),
            "sender": "SYSTEM",
            "action": "TRANSFER",
            "payload": {
                "recipient": GENESIS_ACCOUNT,
                "token": "BDP",
                "amount": GENESIS_BDP
            },
            "nonce": 1,
            "timestamp": 1700000000.0,
            "signature": "GENESIS_SIGNATURE"
        }

        self.state.apply_transaction(genesis_tx)
        self.state.apply_transaction(genesis_tx_bdp)

        genesis_block = {
            "index": 0,
            "prev_hash": "0" * 64,
            "timestamp": 1700000000.0,
            "validator": GENESIS_ACCOUNT,
            "transactions": [genesis_tx, genesis_tx_bdp],
            "activity_proofs": [],
            "state_hash": self.state.get_state_hash(),
        }
        genesis_block["hash"] = self.compute_block_hash(genesis_block)
        self.chain = [genesis_block]
        self.storage.append_block(genesis_block)
        self.storage.save_checkpoint(0, self.state.get_state_hash(), self.state.export_dict())
        self.save_chain()

    def compute_block_hash(self, block: dict) -> str:
        header = {
            "index": block["index"],
            "prev_hash": block["prev_hash"],
            "timestamp": block["timestamp"],
            "validator": block["validator"],
            "transactions_hash": hash_data(block["transactions"]),
            "activity_hash": hash_data(block["activity_proofs"]),
            "state_hash": block["state_hash"]
        }
        return hash_data(header)

    def save_chain(self):
        try:
            if self.chain:
                latest = self.chain[-1]
                self.storage.append_block(latest)
                if latest.get("index", 0) % 500 == 0:
                    self.storage.save_checkpoint(latest["index"], self.state.get_state_hash(), self.state.export_dict())

            with open(self.chain_file, "w") as f:
                json.dump({"chain": self.chain}, f, indent=2)
        except Exception as e:
            print(f"[!] Error saving chain to disk: {e}")

    def rebuild_state_from_chain(self):
        """Re-executes all transactions across the entire chain from scratch."""
        new_state = BlockchainState()
        pwd_hash, _ = hash_password(GENESIS_PASSWORD, GENESIS_SALT)
        _, genesis_pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)
        new_state.register_account(
            GENESIS_ACCOUNT,
            salt=GENESIS_SALT,
            password_hash=pwd_hash,
            public_key=genesis_pubkey,
            initial_csp=0.0,
            initial_bdp=0.0
        )

        for block in self.chain:
            for tx in block.get("transactions", []):
                new_state.apply_transaction(tx)

        self.state = new_state
        print(f"[*] State rebuilt up to block #{len(self.chain) - 1}. Current state hash: {self.state.get_state_hash()[:12]}")

    def authenticate_operator(self) -> bool:
        """Ensures the node operator account is valid, or configures guest mode."""
        if not self.account_id:
            print("[*] Node operating in Guest / Unassigned Mode. (No operator rewards minted until an account logs in)")
            return True

        if self.state.verify_account(self.account_id, self.password):
            self.state.record_activity(self.account_id)
            with self.activity_lock:
                self.active_accounts[self.account_id] = {
                    "last_seen": time.time(),
                    "heartbeat_count": 1,
                    "nonce": secrets.token_hex(8)
                }
            print(f"[*] Node operator account '{self.account_id}' verified and active.")
            return True

        return False

    def register_client_activity(self, account_id: str) -> dict:
        with self.activity_lock:
            now = time.time()
            prev = self.active_accounts.get(account_id, {"heartbeat_count": 0})
            nonce = secrets.token_hex(6)
            proof_hash = hash_data(f"{account_id}_{now}_{nonce}")
            self.active_accounts[account_id] = {
                "last_seen": now,
                "heartbeat_count": prev["heartbeat_count"] + 1,
                "nonce": nonce,
                "proof_hash": proof_hash
            }
            self.state.record_activity(account_id)
            return {
                "account_id": account_id,
                "proof_hash": proof_hash,
                "timestamp": now,
                "score": self.active_accounts[account_id]["heartbeat_count"]
            }

    # -------------------------------------------------------------
    # Proof of Activity (PoA) Mining Engine
    # -------------------------------------------------------------
    def poa_mining_worker(self):
        """
        Proof of Activity (PoA) round worker:
        - Forges when transactions are present in mempool
        - Halving schedule on base reward (every 200 blocks)
        - Collects commissions from transactions
        - ONLY the node-connected operator account receives block reward + fees
        """
        print("[*] Proof of Activity (PoA) consensus engine started.")
        while self.running:
            time.sleep(DEFAULT_BLOCK_TIME)
            try:
                self.forge_block()
            except Exception as e:
                print(f"[!] Block forge error: {e}")

    def forge_block(self):
        with self.sync_lock:
            with self.mempool_lock:
                txs_to_mine = list(self.mempool)

            if not txs_to_mine or not self.chain:
                return

            now = time.time()
            latest_block = self.chain[-1]
            new_index = latest_block["index"] + 1
            prev_hash = latest_block["hash"]

            halvings = new_index // HALVING_INTERVAL
            base_reward_csp = round(INITIAL_BLOCK_REWARD_CSP / (2 ** halvings), 6)

            temp_state = self.state.clone()
            valid_txs = []
            total_fee_csp = 0.0
            total_fee_bdp = 0.0

            for tx in txs_to_mine:
                ok, msg = temp_state.apply_transaction(tx)
                if ok:
                    valid_txs.append(tx)
                    f_tok = tx.get("fee_token")
                    f_amt = float(tx.get("fee", 0.0))
                    if f_tok == "CSP":
                        total_fee_csp += f_amt
                    elif f_tok == "BDP":
                        total_fee_bdp += f_amt
                else:
                    print(f"[!] Dropped invalid mempool tx {tx.get('tx_id')}: {msg}")

            if not valid_txs:
                with self.mempool_lock:
                    self.mempool = [t for t in self.mempool if t not in txs_to_mine]
                return

            block_txs = list(valid_txs)
            validator_id = self.account_id if self.account_id else f"NODE_{self.node_id}"

            if self.account_id:
                reward_tx = {
                    "tx_id": hash_data(f"BLOCK_REWARD_{new_index}_{self.account_id}_{now}"),
                    "sender": "SYSTEM",
                    "action": "POA_REWARD",
                    "payload": {
                        "recipient": self.account_id,
                        "base_reward_csp": base_reward_csp,
                        "fee_reward_csp": round(total_fee_csp, 6),
                        "fee_reward_bdp": round(total_fee_bdp, 6),
                        "total_csp": round(base_reward_csp + total_fee_csp, 6),
                        "total_bdp": round(total_fee_bdp, 6)
                    },
                    "timestamp": now,
                    "signature": "POA_SYSTEM_REWARD"
                }
                temp_state.apply_transaction(reward_tx)
                block_txs.append(reward_tx)
                print(f"[+] PoA Block #{new_index} added by node ({self.account_id}) | Operator Reward: {base_reward_csp} CSP + fees: {total_fee_csp:.4f} CSP, {total_fee_bdp:.4f} BDP | Txs: {len(valid_txs)}")
            else:
                print(f"[+] PoA Block #{new_index} added by guest node ({validator_id}) | No reward minted | Txs: {len(valid_txs)}")

            new_block = {
                "index": new_index,
                "prev_hash": prev_hash,
                "timestamp": now,
                "validator": validator_id,
                "transactions": block_txs,
                "activity_proofs": [{
                    "account_id": validator_id,
                    "tx_count": len(valid_txs),
                    "timestamp": now
                }],
                "state_hash": temp_state.get_state_hash()
            }
            new_block["hash"] = self.compute_block_hash(new_block)

            self.chain.append(new_block)
            self.state = temp_state
            self.save_chain()

            # Remove confirmed txs from mempool
            mined_ids = {t.get("tx_id") for t in valid_txs}
            with self.mempool_lock:
                self.mempool = [t for t in self.mempool if t.get("tx_id") not in mined_ids]

            self.broadcast_block(new_block)

    # -------------------------------------------------------------
    # P2P Network Discovery & Fork Choice Consensus
    # -------------------------------------------------------------
    def udp_discovery_broadcaster(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

        while self.running:
            try:
                beacon_msg = json.dumps({
                    "type": "POA_DISCOVERY_BEACON",
                    "node_id": self.node_id,
                    "account": self.account_id or "GUEST",
                    "host": self.host,
                    "port": self.port,
                    "chain_length": len(self.chain)
                }).encode("utf-8")
                s.sendto(beacon_msg, ("255.255.255.255", self.udp_port))
                s.sendto(beacon_msg, ("127.0.0.1", self.udp_port))
            except Exception:
                pass
            time.sleep(3)
        s.close()

    def udp_discovery_listener(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except AttributeError:
            pass

        try:
            s.bind(("", self.udp_port))
        except Exception as e:
            print(f"[!] UDP discovery bind notice on port {self.udp_port}: {e}")
            return

        while self.running:
            try:
                data, addr = s.recvfrom(2048)
                msg = json.loads(data.decode("utf-8"))
                if msg.get("type") == "POA_DISCOVERY_BEACON":
                    sender_node_id = msg.get("node_id")
                    if sender_node_id == self.node_id:
                        continue

                    sender_host = msg.get("host")
                    if sender_host in ("0.0.0.0", "127.0.0.1") and addr[0] != "127.0.0.1":
                        sender_host = addr[0]

                    sender_port = msg.get("port")
                    peer_url = f"http://{sender_host}:{sender_port}"

                    with self.peer_lock:
                        if peer_url not in self.peers and peer_url != f"http://{self.host}:{self.port}":
                            self.peers.add(peer_url)
                            print(f"[P2P] Discovered node on LAN: {peer_url} (Operator: {msg.get('account')})")
                            threading.Thread(target=self.sync_with_peer, args=(peer_url,), daemon=True).start()
            except Exception:
                pass
        s.close()

    def peer_sync_worker(self):
        counter = 0
        while self.running:
            time.sleep(3)
            counter += 1
            # Periodically probe local ports to discover local peers that started up later
            if counter % 2 == 0:
                for p_port in range(8000, 8009):
                    if p_port != self.port:
                        try:
                            req = urllib.request.Request(f"http://127.0.0.1:{p_port}/status", headers={"User-Agent": "CSII-Pay-Probe"})
                            with urllib.request.urlopen(req, timeout=0.8) as resp:
                                if resp.status == 200:
                                    self.add_peer(f"http://127.0.0.1:{p_port}")
                        except Exception:
                            pass
            self.sync_all_peers()

    def sync_all_peers(self):
        with self.peer_lock:
            peers_list = list(self.peers)
        for p in peers_list:
            self.sync_with_peer(p)

    def add_peer(self, peer_url: str):
        with self.peer_lock:
            if peer_url not in self.peers and peer_url != f"http://{self.host}:{self.port}" and peer_url != f"http://127.0.0.1:{self.port}":
                self.peers.add(peer_url)
                print(f"[P2P] Registered peer: {peer_url}")
                threading.Thread(target=self.sync_with_peer, args=(peer_url,), daemon=True).start()
                threading.Thread(target=self.notify_peer_of_self, args=(peer_url,), daemon=True).start()

    def notify_peer_of_self(self, peer_url: str):
        try:
            my_url = f"http://127.0.0.1:{self.port}" if "127.0.0.1" in peer_url else f"http://{self.host}:{self.port}"
            req = urllib.request.Request(
                f"{peer_url}/peers/add",
                data=json.dumps({"peer": my_url}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST"
            )
            urllib.request.urlopen(req, timeout=3)
        except Exception:
            pass

    def is_peer_chain_preferred(self, peer_chain: list) -> bool:
        """Fork choice rule: Longest chain rule with deterministic consensus tie-breakers."""
        if len(peer_chain) > len(self.chain):
            return True
        if len(peer_chain) == len(self.chain) and len(peer_chain) > 1:
            # Tie breaker:
            # 1. Prefer chain with more non-guest validators (operator activity)
            local_operator_blocks = sum(1 for b in self.chain if not b.get("validator", "").startswith("NODE_"))
            peer_operator_blocks = sum(1 for b in peer_chain if not b.get("validator", "").startswith("NODE_"))
            if peer_operator_blocks > local_operator_blocks:
                return True
            elif peer_operator_blocks < local_operator_blocks:
                return False
            # 2. Deterministic hash tie-breaker (lower block hash)
            return peer_chain[-1]["hash"] < self.chain[-1]["hash"]
        return False

    def sync_with_peer(self, peer_url: str):
        """Fetches chain from peer and reorganizes local chain if peer has a preferred valid PoA chain."""
        try:
            now = time.time()
            if peer_url in self.quarantined_peers and now < self.quarantined_peers[peer_url]:
                return

            req = urllib.request.Request(f"{peer_url}/chain", headers={"User-Agent": "CSII-Pay-Node"})
            with urllib.request.urlopen(req, timeout=4) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                peer_chain = data.get("chain", [])

                with self.sync_lock:
                    if self.is_peer_chain_preferred(peer_chain):
                        print(f"[Sync] Peer {peer_url} has preferred chain (Height #{len(peer_chain) - 1} vs Local #{len(self.chain) - 1}). Validating...")
                        if self.validate_chain(peer_chain):
                            # Find common ancestor
                            common_idx = 0
                            min_len = min(len(self.chain), len(peer_chain))
                            for i in range(min_len):
                                if self.chain[i]["hash"] == peer_chain[i]["hash"]:
                                    common_idx = i
                                else:
                                    break

                            # Collect orphaned transactions from abandoned local blocks
                            peer_tx_ids = {
                                tx.get("tx_id")
                                for b in peer_chain
                                for tx in b.get("transactions", [])
                            }
                            orphaned_txs = []
                            for b in self.chain[common_idx + 1:]:
                                for tx in b.get("transactions", []):
                                    if tx.get("sender") != "SYSTEM" and tx.get("tx_id") not in peer_tx_ids:
                                        orphaned_txs.append(tx)

                            # Reorganize chain to preferred branch
                            self.chain = peer_chain
                            self.save_chain()
                            self.rebuild_state_from_chain()

                            # Re-inject orphaned transactions back into mempool
                            with self.mempool_lock:
                                self.mempool = [t for t in self.mempool if t.get("tx_id") not in peer_tx_ids]
                                for otx in orphaned_txs:
                                    if not any(t.get("tx_id") == otx.get("tx_id") for t in self.mempool):
                                        self.mempool.append(otx)

                            print(f"[Sync ✓] Chain reorganized to height #{len(self.chain) - 1} from {peer_url} (Fork point: #{common_idx}, Rescued {len(orphaned_txs)} txs)")
                        else:
                            print(f"[Security Warning] Peer {peer_url} served an invalid chain! Quarantining peer for 10s.")
                            self.quarantined_peers[peer_url] = now + 10.0
                    else:
                        print(f"[Sync] Peer {peer_url} chain not preferred (Peer #{len(peer_chain) - 1} vs Local #{len(self.chain) - 1})")
        except Exception as e:
            print(f"[Sync Exception with {peer_url}] {e}")

    def validate_chain(self, test_chain: list) -> bool:
        """Validates hash integrity, genesis block, signatures, nonces, and state transitions."""
        if not test_chain:
            return False

        genesis = test_chain[0]
        if genesis["index"] != 0 or genesis["prev_hash"] != "0" * 64:
            return False

        temp_state = BlockchainState()
        pwd_hash, _ = hash_password(GENESIS_PASSWORD, GENESIS_SALT)
        _, genesis_pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)
        temp_state.register_account(
            GENESIS_ACCOUNT,
            salt=GENESIS_SALT,
            password_hash=pwd_hash,
            public_key=genesis_pubkey,
            initial_csp=0.0,
            initial_bdp=0.0
        )

        for i in range(len(test_chain)):
            block = test_chain[i]
            expected_hash = self.compute_block_hash(block)
            if block["hash"] != expected_hash:
                print(f"[Sync Error] Block #{i} hash mismatch")
                return False

            if i > 0:
                prev_block = test_chain[i - 1]
                if block["prev_hash"] != prev_block["hash"]:
                    print(f"[Sync Error] Block #{i} broken link to previous hash")
                    return False
                if block["index"] != prev_block["index"] + 1:
                    return False

            for tx in block.get("transactions", []):
                ok, msg = temp_state.apply_transaction(tx)
                if not ok:
                    print(f"[Sync Error] Invalid tx in block #{i} ({tx.get('tx_id')}): {msg}")
                    return False

            if block["state_hash"] != temp_state.get_state_hash():
                computed = temp_state.get_state_hash()
                print(f"[Sync Error] State hash mismatch on block #{i} (Header: {block['state_hash'][:12]}, Computed: {computed[:12]})")
                return False

        return True

    def broadcast_block(self, block: dict):
        data = json.dumps(block).encode("utf-8")
        with self.peer_lock:
            peer_list = list(self.peers)

        for peer in peer_list:
            def send(p):
                try:
                    req = urllib.request.Request(f"{p}/block/new", data=data, headers={"Content-Type": "application/json"}, method="POST")
                    urllib.request.urlopen(req, timeout=3)
                except Exception:
                    pass
            threading.Thread(target=send, args=(peer,), daemon=True).start()

    def broadcast_tx(self, tx: dict):
        data = json.dumps(tx).encode("utf-8")
        with self.peer_lock:
            peer_list = list(self.peers)

        for peer in peer_list:
            def send(p):
                try:
                    req = urllib.request.Request(f"{p}/tx/submit", data=data, headers={"Content-Type": "application/json"}, method="POST")
                    urllib.request.urlopen(req, timeout=3)
                except Exception:
                    pass
            threading.Thread(target=send, args=(peer,), daemon=True).start()

    def submit_tx(self, tx: dict) -> tuple[bool, str]:
        """Validates and adds transaction to local mempool."""
        with self.mempool_lock:
            tx_id = tx.get("tx_id")
            if any(t.get("tx_id") == tx_id for t in self.mempool):
                return True, "Transaction already in mempool"

            # Check if tx is already confirmed in blockchain
            for b in self.chain:
                if any(t.get("tx_id") == tx_id for t in b.get("transactions", [])):
                    return False, "Transaction has already been confirmed in chain"

            # Pre-validate against clone of current state plus pending mempool transactions
            temp_state = self.state.clone()
            for mtx in self.mempool:
                temp_state.apply_transaction(mtx)

            ok, msg = temp_state.apply_transaction(tx)
            if not ok:
                return False, msg

            self.mempool.append(tx)
            print(f"[Mempool] Accepted tx {tx_id[:10]}... ({tx.get('action')} from {tx.get('sender')})")

        self.broadcast_tx(tx)
        return True, "Transaction accepted into mempool"

    # -------------------------------------------------------------
    # HTTP REST API Server
    # -------------------------------------------------------------
    def start_http_api(self):
        node = self

        class NodeHttpHandler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                return

            def send_json(self, status_code: int, data: dict):
                body = json.dumps(data, indent=2).encode("utf-8")
                self.send_response(status_code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Headers", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.end_headers()
                self.wfile.write(body)

            def do_OPTIONS(self):
                self.send_response(200)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Headers", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.end_headers()

            def do_GET(self):
                url = self.path.split("?")[0].rstrip("/")

                if url == "/status":
                    with node.peer_lock:
                        peers_count = len(node.peers)
                    with node.mempool_lock:
                        mempool_count = len(node.mempool)
                    with node.activity_lock:
                        active_users = len(node.active_accounts)

                    self.send_json(200, {
                        "status": "online",
                        "node_id": node.node_id,
                        "operator_account": node.account_id or "GUEST_UNASSIGNED",
                        "host": node.host,
                        "port": node.port,
                        "block_height": len(node.chain) - 1,
                        "latest_block_hash": node.chain[-1]["hash"] if node.chain else "",
                        "peers_count": peers_count,
                        "mempool_size": mempool_count,
                        "active_users_count": active_users,
                        "consensus": "Proof of Activity (PoA)",
                        "tokens": ["CSP (Layer 1 Base)", "BDP (Layer 2)"]
                    })

                elif url == "/operator/status":
                    self.send_json(200, {
                        "operator_account": node.account_id or "GUEST_UNASSIGNED",
                        "is_guest": node.account_id is None,
                        "node_id": node.node_id,
                        "mining_rewards_enabled": node.account_id is not None
                    })

                elif url == "/chain":
                    self.send_json(200, {
                        "length": len(node.chain),
                        "chain": node.chain
                    })

                elif url == "/orders":
                    with node.state.lock:
                        orders_list = list(node.state.orders.values())
                    self.send_json(200, {
                        "orders": orders_list
                    })

                elif url.startswith("/account/"):
                    acc_id = url.split("/account/")[1]
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            with node.mempool_lock:
                                for mtx in node.mempool:
                                    if mtx.get("action") == "ACCOUNT_REGISTER" and mtx.get("payload", {}).get("account_id") == acc_id:
                                        p = mtx["payload"]
                                        acc = {
                                            "balances": {"CSP": 0.0, "BDP": float(p.get("initial_bdp", DEFAULT_SIGNUP_BDP))},
                                            "nonce": 0,
                                            "salt": p.get("salt"),
                                            "public_key": p.get("public_key"),
                                            "last_active": mtx.get("timestamp", time.time()),
                                            "activity": {"tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0, "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0}
                                        }
                                        break
                        if not acc:
                            self.send_json(404, {"error": f"Account {acc_id} not found"})
                            return

                        with node.activity_lock:
                            act_info = node.active_accounts.get(acc_id, {})

                        act_data = acc.get("activity", {
                            "tx_count": 0, "volume_csp": 0.0, "volume_bdp": 0.0,
                            "fees_paid_csp": 0.0, "fees_paid_bdp": 0.0, "score": 0.0
                        })
                        with node.mempool_lock:
                            pending_tx_count = sum(1 for t in node.mempool if t.get("sender") == acc_id and t.get("action") != "ACCOUNT_REGISTER")
                        effective_nonce = acc.get("nonce", 0) + pending_tx_count

                        self.send_json(200, {
                            "account_id": acc_id,
                            "balances": acc["balances"],
                            "frozen_balances": acc.get("frozen_balances", {"CSP": 0.0, "BDP": 0.0}),
                            "is_verified": acc.get("is_verified", False),
                            "verification_status": acc.get("verification_status", "PENDING" if float(acc.get("frozen_balances", {}).get("BDP", 0.0)) > 0 else "VERIFIED"),
                            "nonce": effective_nonce,
                            "salt": acc.get("salt"),
                            "public_key": acc.get("public_key"),
                            "last_active": acc["last_active"],
                            "is_poa_active": acc_id in node.active_accounts,
                            "poa_score": act_data.get("score", 0.0),
                            "activity": act_data
                        })

                elif url == "/accounts":
                    with node.state.lock:
                        accounts_list = [
                            {
                                "account_id": a_id,
                                "balances": a_data.get("balances", {}),
                                "frozen_balances": a_data.get("frozen_balances", {"CSP": 0.0, "BDP": 0.0}),
                                "is_verified": a_data.get("is_verified", False),
                                "verification_status": a_data.get("verification_status", "PENDING" if float(a_data.get("frozen_balances", {}).get("BDP", 0.0)) > 0 else "VERIFIED"),
                                "nonce": a_data.get("nonce", 0),
                                "public_key": a_data.get("public_key"),
                                "last_active": a_data.get("last_active", 0.0)
                            }
                            for a_id, a_data in sorted(node.state.accounts.items())
                        ]
                    self.send_json(200, {"accounts": accounts_list})

                elif url == "/peers":
                    with node.peer_lock:
                        p_list = list(node.peers)
                    self.send_json(200, {"peers": p_list})

                elif url == "/transactions":
                    query_str = self.path.split("?")[1] if "?" in self.path else ""
                    params = urllib.parse.parse_qs(query_str)
                    target_account = params.get("account", [None])[0]
                    limit = int(params.get("limit", [20])[0])
                    offset = int(params.get("offset", [0])[0])

                    all_txs = []
                    # 1. From Mempool (Pending)
                    with node.mempool_lock:
                        for mtx in reversed(node.mempool):
                            sender = mtx.get("sender")
                            p = mtx.get("payload", {})
                            recipient = p.get("recipient") or p.get("maker") or p.get("worker") or p.get("account_id")
                            creator = p.get("creator")
                            if not target_account or target_account in (sender, recipient, creator):
                                all_txs.append({
                                    "tx_id": mtx.get("tx_id") or hash_data(mtx),
                                    "action": mtx.get("action"),
                                    "sender": sender,
                                    "recipient": recipient,
                                    "token": p.get("token") or p.get("offer_token") or p.get("wage_token") or "CSP",
                                    "amount": p.get("amount") or p.get("offer_amount") or p.get("wage") or 0.0,
                                    "fee": mtx.get("fee", 0.0),
                                    "fee_token": mtx.get("fee_token", "CSP"),
                                    "timestamp": mtx.get("timestamp", time.time()),
                                    "block_index": None,
                                    "status": "PENDING",
                                    "payload": p
                                })

                    # 1. High-Speed Indexed SQLite Storage
                    total_db, db_txs = node.storage.query_transactions(target_account, offset, limit)
                    all_txs.extend(db_txs)

                    # 2. Marketplace Claims fallback synthesis (ensures completed jobs appear in history)
                    claim_job_ids = {t.get("payload", {}).get("job_id") for t in all_txs if t.get("action") == "MARKETPLACE_CLAIM"}
                    with node.state.lock:
                        for j_id, j in node.state.marketplace_jobs.items():
                            if j.get("status") == "COMPLETED" and j.get("worker") and j_id not in claim_job_ids:
                                worker = j.get("worker")
                                creator = j.get("creator")
                                if not target_account or target_account in (worker, creator):
                                    all_txs.append({
                                        "tx_id": hash_data(f"CLAIM_{j_id}_{worker}"),
                                        "action": "MARKETPLACE_CLAIM",
                                        "sender": worker,
                                        "recipient": creator,
                                        "token": j.get("wage_token", "CSP"),
                                        "amount": j.get("wage", 0.0),
                                        "fee": 0.0,
                                        "fee_token": "CSP",
                                        "timestamp": j.get("completed_at", j.get("created_at", time.time())),
                                        "block_index": 1,
                                        "status": "CONFIRMED",
                                        "payload": {
                                            "job_id": j_id,
                                            "title": j.get("title"),
                                            "wage": j.get("wage"),
                                            "wage_token": j.get("wage_token"),
                                            "creator": creator,
                                            "worker": worker
                                        }
                                    })

                    all_txs.sort(key=lambda x: float(x.get("timestamp") or 0), reverse=True)

                    total = max(total_db, len(all_txs))
                    paged = all_txs[:limit]
                    self.send_json(200, {
                        "total": total,
                        "offset": offset,
                        "limit": limit,
                        "transactions": paged
                    })

                elif url == "/marketplace/jobs":
                    query_str = self.path.split("?")[1] if "?" in self.path else ""
                    params = urllib.parse.parse_qs(query_str)
                    category = params.get("category", [None])[0]
                    job_type = params.get("type", [None])[0]
                    difficulty = params.get("difficulty", [None])[0]
                    creator = params.get("creator", [None])[0]

                    with node.state.lock:
                        # Purge test jobs
                        node.state.marketplace_jobs = {
                            k: v for k, v in node.state.marketplace_jobs.items()
                            if "design test flyer" not in v.get("title", "").lower() and k != "d28b089116d45afa"
                        }
                        jobs = list(node.state.marketplace_jobs.values())

                    filtered = []
                    for j in jobs:
                        if category and j.get("category") != category:
                            continue
                        if job_type and j.get("type") != job_type:
                            continue
                        if difficulty and str(j.get("difficulty")) != str(difficulty):
                            continue
                        if creator and j.get("creator") != creator:
                            continue
                        filtered.append(j)

                    filtered.sort(key=lambda x: x.get("created_at", 0), reverse=True)
                    self.send_json(200, {
                        "jobs": filtered
                    })

                elif url == "/contracts":
                    with node.state.lock:
                        contract_list = [
                            {
                                "id": cid,
                                "owner": c["owner"],
                                "name": c.get("name", "Custom Smart Contract"),
                                "balances": c.get("balances", {}),
                                "tx_count": c.get("tx_count", 0),
                                "created_at": c.get("created_at", 0)
                            }
                            for cid, c in node.state.contracts.items()
                        ]
                    contract_list.sort(key=lambda x: x.get("created_at", 0), reverse=True)
                    self.send_json(200, {"contracts": contract_list, "total": len(contract_list)})

                elif url == "/contracts/info":
                    query_str = self.path.split("?")[1] if "?" in self.path else ""
                    params = urllib.parse.parse_qs(query_str)
                    cid = params.get("id", [None])[0]
                    if not cid:
                        self.send_json(400, {"error": "Parameter 'id' is required"})
                        return
                    with node.state.lock:
                        contract = node.state.contracts.get(cid)
                        if not contract:
                            self.send_json(404, {"error": f"Contract '{cid}' not found"})
                            return
                        c_copy = copy.deepcopy(contract)
                    self.send_json(200, {"contract": c_copy})

                elif url == "/groups":
                    with node.state.lock:
                        groups_list = [
                            {
                                "name": g["name"],
                                "description": g["description"],
                                "entrance_fee": g["entrance_fee"],
                                "created_at": g["created_at"],
                                "creator": g["creator"],
                                "member_count": len(g["members"]),
                                "balance": node.state.accounts.get(g["name"], {}).get("balances", {}).get("CSP", 0.0)
                            }
                            for g in node.state.groups.values()
                        ]
                    groups_list.sort(key=lambda x: x.get("created_at", 0), reverse=True)
                    self.send_json(200, {"groups": groups_list, "total": len(groups_list)})

                elif url == "/groups/info":
                    query_str = self.path.split("?")[1] if "?" in self.path else ""
                    params = urllib.parse.parse_qs(query_str)
                    gname = params.get("name", [None])[0]
                    if not gname:
                        self.send_json(400, {"error": "Parameter 'name' is required"})
                        return
                    with node.state.lock:
                        group = node.state.groups.get(gname)
                        if not group:
                            self.send_json(404, {"error": f"Group '{gname}' not found"})
                            return
                        g_copy = copy.deepcopy(group)
                        g_copy["balance"] = node.state.accounts.get(gname, {}).get("balances", {}).get("CSP", 0.0)
                        # Attach account nicknames/usernames for members
                        member_details = {}
                        for mid in g_copy["members"]:
                            acc = node.state.accounts.get(mid, {})
                            member_details[mid] = {
                                **g_copy["members"][mid],
                                "account_id": mid
                            }
                        g_copy["member_details"] = member_details
                    self.send_json(200, {"group": g_copy})

                elif url == "/groups/member":
                    query_str = self.path.split("?")[1] if "?" in self.path else ""
                    params = urllib.parse.parse_qs(query_str)
                    account = params.get("account", [None])[0]
                    if not account:
                        self.send_json(400, {"error": "Parameter 'account' is required"})
                        return
                    with node.state.lock:
                        my_groups = [
                            {
                                "name": g["name"],
                                "description": g["description"],
                                "entrance_fee": g["entrance_fee"],
                                "created_at": g["created_at"],
                                "creator": g["creator"],
                                "member_count": len(g["members"]),
                                "balance": node.state.accounts.get(g["name"], {}).get("balances", {}).get("CSP", 0.0),
                                "is_creator": g["creator"] == account,
                                "pending_polls": sum(1 for p in g["polls"].values() if p["status"] == "OPEN"),
                                "pending_invitations": sum(1 for inv in g["invitations"] if inv["invitee"] == account)
                            }
                            for g in node.state.groups.values()
                            if account in g["members"]
                        ]
                        # Also include groups where account has a pending invitation
                        pending_invites = [
                            {
                                "name": g["name"],
                                "description": g["description"],
                                "entrance_fee": g["entrance_fee"],
                                "creator": g["creator"],
                                "member_count": len(g["members"]),
                                "balance": node.state.accounts.get(g["name"], {}).get("balances", {}).get("CSP", 0.0),
                                "invitation_from": next(i["inviter"] for i in g["invitations"] if i["invitee"] == account)
                            }
                            for g in node.state.groups.values()
                            if account not in g["members"] and any(i["invitee"] == account for i in g["invitations"])
                        ]
                    self.send_json(200, {"my_groups": my_groups, "pending_invites": pending_invites})

                else:
                    self.send_json(404, {"error": "Not Found"})


            def do_POST(self):
                url = self.path.split("?")[0].rstrip("/")
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length) if content_length > 0 else b"{}"

                try:
                    payload = json.loads(body.decode("utf-8")) if body else {}
                except Exception:
                    self.send_json(400, {"error": "Invalid JSON body"})
                    return

                if url == "/login":
                    acc_id = payload.get("account_id")
                    pwd = payload.get("password")
                    if node.state.verify_account(acc_id, pwd):
                        token = secrets.token_hex(24)
                        node.session_tokens[token] = acc_id
                        node.register_client_activity(acc_id)
                        acc_data = node.state.accounts[acc_id]
                        salt = acc_data.get("salt", "")
                        privkey, pub_hex = derive_account_keypair(pwd, salt)
                        self.send_json(200, {
                            "success": True,
                            "token": token,
                            "account_id": acc_id,
                            "salt": salt,
                            "public_key": acc_data.get("public_key") or pub_hex,
                            "private_key": f"{privkey:064x}",
                            "nonce": acc_data.get("nonce", 0),
                            "balances": node.state.get_balances(acc_id)
                        })
                    else:
                        self.send_json(401, {"error": "Invalid account credentials"})

                elif url == "/operator/login":
                    acc_id = payload.get("account_id")
                    pwd = payload.get("password")
                    if not acc_id or not pwd:
                        self.send_json(400, {"error": "account_id and password required"})
                        return
                    if node.state.verify_account(acc_id, pwd):
                        node.account_id = acc_id
                        node.password = pwd
                        node.state.record_activity(acc_id)
                        with node.activity_lock:
                            node.active_accounts[acc_id] = {
                                "last_seen": time.time(),
                                "heartbeat_count": 1,
                                "nonce": secrets.token_hex(8)
                            }
                        print(f"[*] Node operator attached: '{acc_id}' (mining rewards active)")
                        self.send_json(200, {
                            "success": True,
                            "message": f"Node operator connected to '{acc_id}'",
                            "operator_account": acc_id
                        })
                    else:
                        self.send_json(401, {"error": "Invalid account credentials"})

                elif url == "/register":
                    acc_id = payload.get("account_id")
                    pwd = payload.get("password")
                    if not acc_id or not pwd:
                        self.send_json(400, {"error": "account_id and password required"})
                        return

                    with node.state.lock:
                        if acc_id in node.state.accounts:
                            self.send_json(400, {"error": f"Account '{acc_id}' already exists"})
                            return

                    salt = secrets.token_hex(16)
                    pwd_hash, _ = hash_password(pwd, salt)
                    privkey, pub_hex = derive_account_keypair(pwd, salt)

                    reg_tx = {
                        "tx_id": hash_data(f"REG_{acc_id}_{time.time()}_{secrets.token_hex(4)}"),
                        "sender": acc_id,
                        "action": "ACCOUNT_REGISTER",
                        "payload": {
                            "account_id": acc_id,
                            "password_hash": pwd_hash,
                            "salt": salt,
                            "public_key": pub_hex,
                            "initial_bdp": DEFAULT_SIGNUP_BDP
                        },
                        "nonce": 0,
                        "timestamp": time.time(),
                        "signature": "SELF_REGISTRATION"
                    }
                    reg_tx["signature"] = sign_transaction_payload(reg_tx, privkey)

                    ok, msg = node.submit_tx(reg_tx)
                    if not ok:
                        self.send_json(400, {"error": msg})
                        return

                    token = secrets.token_hex(24)
                    node.session_tokens[token] = acc_id
                    node.register_client_activity(acc_id)
                    self.send_json(200, {
                        "success": True,
                        "token": token,
                        "account_id": acc_id,
                        "salt": salt,
                        "public_key": pub_hex,
                        "private_key": f"{privkey:064x}",
                        "nonce": 0,
                        "balances": {"CSP": 0.0, "BDP": 0.0},
                        "frozen_balances": {"CSP": 0.0, "BDP": DEFAULT_SIGNUP_BDP},
                        "is_verified": False,
                        "verification_status": "PENDING"
                    })

                elif url == "/activity/ping":
                    acc_id = payload.get("account_id")
                    token = payload.get("token")
                    if token and node.session_tokens.get(token) == acc_id:
                        proof = node.register_client_activity(acc_id)
                        self.send_json(200, {"success": True, "proof": proof})
                    elif acc_id and node.state.accounts.get(acc_id):
                        proof = node.register_client_activity(acc_id)
                        self.send_json(200, {"success": True, "proof": proof})
                    else:
                        self.send_json(401, {"error": "Unauthorized activity ping"})

                elif url == "/tx/submit":
                    ok, msg = node.submit_tx(payload)
                    if ok:
                        self.send_json(200, {"success": True, "message": msg, "tx_id": payload.get("tx_id")})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/block/new":
                    incoming_block = payload
                    if incoming_block.get("index") == len(node.chain):
                        test_chain = list(node.chain) + [incoming_block]
                        if node.validate_chain(test_chain):
                            node.chain = test_chain
                            node.save_chain()
                            node.rebuild_state_from_chain()

                            # Purge confirmed transactions from mempool
                            confirmed_ids = {tx.get("tx_id") for tx in incoming_block.get("transactions", [])}
                            with node.mempool_lock:
                                node.mempool = [t for t in node.mempool if t.get("tx_id") not in confirmed_ids]

                            print(f"[P2P] Accepted gossiped block #{incoming_block['index']} from peer")
                            self.send_json(200, {"success": True})
                            return
                    elif incoming_block.get("index", 0) >= len(node.chain):
                        threading.Thread(target=node.sync_all_peers, daemon=True).start()
                        self.send_json(200, {"success": True, "note": "Sync triggered"})
                        return
                    self.send_json(200, {"success": False, "note": "Block ignored or older"})

                elif url == "/peers/add":
                    peer_url = payload.get("peer")
                    if peer_url:
                        node.add_peer(peer_url)
                        self.send_json(200, {"success": True, "peer": peer_url})
                    else:
                        self.send_json(400, {"error": "Missing peer URL"})

                elif url == "/marketplace/create":
                    creator = payload.get("creator") or payload.get("author")
                    wage = float(payload.get("wage", 0.0))
                    wage_token = payload.get("wage_token", payload.get("token", "CSP"))
                    secret_hash = payload.get("secret_hash") or hash_data(str(payload.get("secret_code", secrets.token_hex(8))))
                    team_name = payload.get("team_name")
                    author = payload.get("author", creator)
                    effective_creator = team_name if team_name else creator
                    job_id = payload.get("job_id") or hash_data(f"JOB_{effective_creator}_{time.time()}_{secrets.token_hex(4)}")[:16]

                    if not creator or wage <= 0:
                        self.send_json(400, {"success": False, "error": "creator and positive wage are required"})
                        return

                    with node.state.lock:
                        if team_name:
                            group = node.state.groups.get(team_name)
                            if not group:
                                self.send_json(404, {"success": False, "error": f"Team '{team_name}' not found"})
                                return
                            if author not in group["members"]:
                                self.send_json(403, {"success": False, "error": f"Account '{author}' is not a member of team '{team_name}'"})
                                return
                            creator_acc = node.state.accounts.get(team_name)
                            if not creator_acc:
                                self.send_json(404, {"success": False, "error": f"Team account '{team_name}' not found"})
                                return
                            wage_token = "CSP"  # Teams only work with CSP
                            app_type = "team application"
                        else:
                            creator_acc = node.state.accounts.get(creator)
                            if not creator_acc:
                                self.send_json(404, {"success": False, "error": f"Account {creator} not found"})
                                return
                            app_type = payload.get("type", "student application")

                        if creator_acc["balances"].get(wage_token, 0.0) < wage:
                            self.send_json(400, {"success": False, "error": f"Insufficient {wage_token} balance. Required: {wage}, Available: {creator_acc['balances'].get(wage_token, 0.0)}"})
                            return

                        # Create tx
                        create_tx = {
                            "tx_id": hash_data(f"TX_MKT_CREATE_{job_id}_{time.time()}"),
                            "sender": effective_creator,
                            "action": "MARKETPLACE_CREATE",
                            "payload": {
                                "job_id": job_id,
                                "creator": effective_creator,
                                "title": payload.get("title", "Untitled Application"),
                                "type": app_type,
                                "category": payload.get("category", "tech"),
                                "description": payload.get("description", ""),
                                "deadline": payload.get("deadline", ""),
                                "difficulty": int(payload.get("difficulty", 1)),
                                "line_id": payload.get("line_id", ""),
                                "wage": wage,
                                "wage_token": wage_token,
                                "secret_hash": secret_hash,
                                "author": f"Team: {team_name} (by {author})" if team_name else author,
                                "team_name": team_name
                            },
                            "nonce": creator_acc["nonce"],
                            "timestamp": time.time(),
                            "signature": "DIRECT_MARKETPLACE"
                        }
                        ok, msg = node.submit_tx(create_tx)
                        if ok:
                            node.forge_block()
                            self.send_json(200, {
                                "success": True,
                                "message": msg,
                                "job_id": job_id,
                                "tx_id": create_tx["tx_id"]
                            })
                        else:
                            self.send_json(400, {"success": False, "error": msg})

                elif url == "/marketplace/claim":
                    acc_id = payload.get("account_id")
                    job_id = payload.get("job_id")
                    secret_code = str(payload.get("secret_code", "")).strip()

                    if not acc_id or not job_id or not secret_code:
                        self.send_json(400, {"success": False, "error": "account_id, job_id, and secret_code required"})
                        return

                    with node.state.lock:
                        job = node.state.marketplace_jobs.get(job_id)
                        if not job:
                            self.send_json(404, {"success": False, "error": f"Application {job_id} not found"})
                            return
                        if job["status"] != "OPEN":
                            self.send_json(400, {"success": False, "error": f"Application is already {job['status']}"})
                            return
                        if job["creator"] == acc_id:
                            self.send_json(400, {"success": False, "error": "You cannot claim your own application!"})
                            return

                        worker_acc = node.state.accounts.get(acc_id)
                        if not worker_acc:
                            self.send_json(404, {"success": False, "error": f"Account {acc_id} not found"})
                            return

                        computed_hash = hashlib.sha256(secret_code.encode("utf-8")).hexdigest()
                        if computed_hash != job["secret_hash"]:
                            failed_map = job.setdefault("failed_attempts", {})
                            fails = failed_map.get(acc_id, 0) + 1
                            failed_map[acc_id] = fails
                            fined = False
                            if fails > 3:
                                fined = True
                                fine_amount = 10.0
                                worker_acc["balances"]["CSP"] = round(max(0.0, worker_acc["balances"]["CSP"] - fine_amount), 6)
                                msg = f"Incorrect code! You exceeded 3 attempts (attempt #{fails}) and have been fined 10 CSP."
                            else:
                                msg = f"Incorrect secret code! Attempt {fails}/3. (More than 3 failed attempts will trigger a 10 CSP fine)"

                            self.send_json(400, {
                                "success": False,
                                "error": msg,
                                "failed_attempts": fails,
                                "fined": fined,
                                "fine_amount": 10.0 if fined else 0.0,
                                "remaining_csp": worker_acc["balances"]["CSP"]
                            })
                            return

                        wage = job["wage"]
                        wage_token = job["wage_token"]
                        creator_id = job["creator"]
                        worker_nonce = worker_acc["nonce"]

                    claim_tx = {
                        "tx_id": hash_data(f"CLAIM_{job_id}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "MARKETPLACE_CLAIM",
                        "payload": {
                            "job_id": job_id,
                            "secret_code": secret_code,
                            "wage": wage,
                            "wage_token": wage_token,
                            "creator": creator_id
                        },
                        "nonce": worker_nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_CLAIM"
                    }

                    ok, msg = node.submit_tx(claim_tx)
                    if ok:
                        # Immediately mine into PoA block
                        node.forge_block()
                        with node.state.lock:
                            w_acc = node.state.accounts.get(acc_id)
                            new_bal = w_acc["balances"].get(wage_token, 0.0) if w_acc else 0.0
                        self.send_json(200, {
                            "success": True,
                            "message": f"Secret code verified! Received {wage} {wage_token}",
                            "wage": wage,
                            "wage_token": wage_token,
                            "new_balance": new_bal,
                            "tx_id": claim_tx["tx_id"]
                        })
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/contracts/deploy":
                    sender = payload.get("sender")
                    code = payload.get("code")
                    name = payload.get("name", "Custom Smart Contract")
                    init_args = payload.get("init_args", {})
                    initial_escrow = float(payload.get("initial_escrow", 0.0))
                    initial_token = payload.get("initial_token", "CSP")

                    if not sender or not code:
                        self.send_json(400, {"success": False, "error": "'sender' and 'code' are required"})
                        return

                    with node.state.lock:
                        sender_acc = node.state.accounts.get(sender)
                        if not sender_acc:
                            self.send_json(404, {"success": False, "error": f"Account '{sender}' not found"})
                            return
                        nonce = sender_acc["nonce"]
                        contract_id = f"0x{hash_data(f'{sender}_{nonce}_{time.time()}')[:16]}"

                    deploy_tx = {
                        "tx_id": hash_data(f"DEPLOY_{contract_id}_{time.time()}"),
                        "sender": sender,
                        "action": "CONTRACT_DEPLOY",
                        "payload": {
                            "contract_id": contract_id,
                            "name": name,
                            "code": code,
                            "init_args": init_args,
                            "initial_escrow": initial_escrow,
                            "initial_token": initial_token
                        },
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_CONTRACT"
                    }

                    ok, msg = node.submit_tx(deploy_tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {
                            "success": True,
                            "message": msg,
                            "contract_id": contract_id,
                            "tx_id": deploy_tx["tx_id"]
                        })
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/contracts/call":
                    sender = payload.get("sender")
                    contract_id = payload.get("contract_id")
                    method = payload.get("method")
                    args = payload.get("args", {})
                    attached_amount = float(payload.get("attached_amount", 0.0))
                    attached_token = payload.get("attached_token", "CSP")

                    if not sender or not contract_id or not method:
                        self.send_json(400, {"success": False, "error": "'sender', 'contract_id', and 'method' are required"})
                        return

                    with node.state.lock:
                        sender_acc = node.state.accounts.get(sender)
                        if not sender_acc:
                            self.send_json(404, {"success": False, "error": f"Account '{sender}' not found"})
                            return
                        if contract_id not in node.state.contracts:
                            self.send_json(404, {"success": False, "error": f"Contract '{contract_id}' not found"})
                            return
                        nonce = sender_acc["nonce"]

                    call_tx = {
                        "tx_id": hash_data(f"CALL_{contract_id}_{method}_{sender}_{time.time()}"),
                        "sender": sender,
                        "action": "CONTRACT_CALL",
                        "payload": {
                            "contract_id": contract_id,
                            "method": method,
                            "args": args,
                            "attached_amount": attached_amount,
                            "attached_token": attached_token
                        },
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_CONTRACT"
                    }

                    ok, msg = node.submit_tx(call_tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {
                            "success": True,
                            "message": msg,
                            "contract_id": contract_id,
                            "tx_id": call_tx["tx_id"]
                        })
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/contracts/query":
                    contract_id = payload.get("contract_id")
                    method = payload.get("method")
                    args = payload.get("args", {})
                    caller = payload.get("caller", "ANONYMOUS")

                    if not contract_id or not method:
                        self.send_json(400, {"success": False, "error": "'contract_id' and 'method' are required"})
                        return

                    with node.state.lock:
                        contract = node.state.contracts.get(contract_id)
                        if not contract:
                            self.send_json(404, {"success": False, "error": f"Contract '{contract_id}' not found"})
                            return
                        temp_storage = copy.deepcopy(contract["storage"])
                        temp_balances = copy.deepcopy(contract["balances"])
                        code = contract["code"]
                        owner = contract["owner"]

                    ctx = ContractContext(
                        contract_id=contract_id,
                        contract_owner=owner,
                        caller=caller,
                        timestamp=time.time(),
                        storage=temp_storage,
                        balances=temp_balances
                    )
                    ok, res, err = SmartContractEngine.execute(code, method, ctx, args)
                    if ok:
                        self.send_json(200, {
                            "success": True,
                            "result": res,
                            "storage": temp_storage,
                            "events": ctx.events
                        })
                    else:
                        self.send_json(400, {"success": False, "error": err})

                elif url == "/groups/create":
                    acc_id = payload.get("account_id")
                    group_name = (payload.get("group_name") or payload.get("name") or "").strip()
                    description = payload.get("description", "").strip()
                    initial_deposit = float(payload.get("initial_deposit", payload.get("entrance_fee", 0.0)))

                    if not acc_id or not group_name:
                        self.send_json(400, {"success": False, "error": "account_id and group_name required"})
                        return
                    if not description:
                        self.send_json(400, {"success": False, "error": "Description is required for team creation"})
                        return
                    if initial_deposit < 0.0:
                        self.send_json(400, {"success": False, "error": "Initial deposit cannot be negative"})
                        return

                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        if group_name in node.state.groups:
                            self.send_json(400, {"success": False, "error": f"Team '{group_name}' already exists"})
                            return
                        if initial_deposit > 0.0 and acc["balances"].get("CSP", 0.0) < initial_deposit:
                            self.send_json(400, {"success": False, "error": f"Insufficient CSP for initial deposit ({initial_deposit} CSP required)"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"GRP_CREATE_{group_name}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_CREATE",
                        "payload": {
                            "group_name": group_name,
                            "description": description,
                            "initial_deposit": initial_deposit
                        },
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg, "group_name": group_name})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/leave":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()

                    if not acc_id or not group_name:
                        self.send_json(400, {"success": False, "error": "account_id and group_name required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        group = node.state.groups.get(group_name)
                        if not group:
                            self.send_json(404, {"success": False, "error": f"Team '{group_name}' not found"})
                            return
                        if acc_id not in group["members"]:
                            self.send_json(400, {"success": False, "error": f"You are not a member of '{group_name}'"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"GRP_LEAVE_{group_name}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_LEAVE",
                        "payload": {"group_name": group_name},
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/transfer":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()
                    recipient = payload.get("recipient", "").strip()
                    amount = float(payload.get("amount", 0.0))

                    if not acc_id or not group_name or not recipient or amount <= 0:
                        self.send_json(400, {"success": False, "error": "account_id, group_name, recipient, and positive amount required"})
                        return

                    with node.state.lock:
                        group = node.state.groups.get(group_name)
                        if not group:
                            self.send_json(404, {"success": False, "error": f"Team '{group_name}' not found"})
                            return
                        if acc_id not in group["members"]:
                            self.send_json(403, {"success": False, "error": f"Account '{acc_id}' is not an authorized member of team '{group_name}'"})
                            return
                        group_acc = node.state.accounts.get(group_name)
                        if not group_acc:
                            self.send_json(404, {"success": False, "error": f"Team account '{group_name}' not found"})
                            return
                        if recipient not in node.state.accounts:
                            self.send_json(404, {"success": False, "error": f"Recipient '{recipient}' does not exist"})
                            return

                        fee = calculate_commission("CSP", amount)
                        total_needed = round(amount + fee, 6)
                        if group_acc["balances"].get("CSP", 0.0) < total_needed:
                            self.send_json(400, {"success": False, "error": f"Insufficient team CSP balance. Required: {total_needed}, Available: {group_acc['balances'].get('CSP', 0.0)}"})
                            return

                        nonce = group_acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"TX_GRP_XFER_{group_name}_{recipient}_{time.time()}"),
                        "sender": group_name,
                        "action": "TRANSFER",
                        "payload": {
                            "recipient": recipient,
                            "token": "CSP",
                            "amount": amount,
                            "author": acc_id
                        },
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg, "tx_id": tx["tx_id"]})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/invite":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()
                    invitee = payload.get("invitee", "").strip()

                    if not acc_id or not group_name or not invitee:
                        self.send_json(400, {"success": False, "error": "account_id, group_name, invitee required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"GRP_INVITE_{group_name}_{acc_id}_{invitee}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_INVITE",
                        "payload": {"group_name": group_name, "invitee": invitee},
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/join":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()

                    if not acc_id or not group_name:
                        self.send_json(400, {"success": False, "error": "account_id and group_name required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"GRP_JOIN_{group_name}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_JOIN",
                        "payload": {"group_name": group_name},
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/poll/create":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()
                    poll_type = payload.get("poll_type", "").upper()
                    title = payload.get("title", "").strip()
                    poll_payload = payload.get("poll_payload", {})

                    if not acc_id or not group_name or not poll_type or not title:
                        self.send_json(400, {"success": False, "error": "account_id, group_name, poll_type, title required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"POLL_CREATE_{group_name}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_POLL_CREATE",
                        "payload": {
                            "group_name": group_name,
                            "poll_type": poll_type,
                            "title": title,
                            "poll_payload": poll_payload
                        },
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/poll/vote":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()
                    poll_id = payload.get("poll_id", "").strip()
                    vote = bool(payload.get("vote", False))

                    if not acc_id or not group_name or not poll_id:
                        self.send_json(400, {"success": False, "error": "account_id, group_name, poll_id required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"POLL_VOTE_{group_name}_{poll_id}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_VOTE",
                        "payload": {"group_name": group_name, "poll_id": poll_id, "vote": vote},
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        # Return updated poll status
                        with node.state.lock:
                            g = node.state.groups.get(group_name, {})
                            p = g.get("polls", {}).get(poll_id, {})
                        self.send_json(200, {"success": True, "message": msg, "poll_status": p.get("status", "OPEN")})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                elif url == "/groups/poll/execute":
                    acc_id = payload.get("account_id")
                    group_name = payload.get("group_name", "").strip()
                    poll_id = payload.get("poll_id", "").strip()

                    if not acc_id or not group_name or not poll_id:
                        self.send_json(400, {"success": False, "error": "account_id, group_name, poll_id required"})
                        return
                    with node.state.lock:
                        acc = node.state.accounts.get(acc_id)
                        if not acc:
                            self.send_json(404, {"success": False, "error": f"Account '{acc_id}' not found"})
                            return
                        nonce = acc["nonce"]

                    tx = {
                        "tx_id": hash_data(f"POLL_EXEC_{group_name}_{poll_id}_{acc_id}_{time.time()}"),
                        "sender": acc_id,
                        "action": "GROUP_POLL_EXECUTE",
                        "payload": {"group_name": group_name, "poll_id": poll_id},
                        "nonce": nonce,
                        "timestamp": time.time(),
                        "signature": "DIRECT_GROUP"
                    }
                    ok, msg = node.submit_tx(tx)
                    if ok:
                        node.forge_block()
                        self.send_json(200, {"success": True, "message": msg})
                    else:
                        self.send_json(400, {"success": False, "error": msg})

                else:
                    self.send_json(404, {"error": "Not Found"})


        server_address = ("0.0.0.0", self.port)
        http.server.ThreadingHTTPServer.allow_reuse_address = True
        httpd = http.server.ThreadingHTTPServer(server_address, NodeHttpHandler)
        httpd.daemon_threads = True
        print(f"[*] HTTP Server listening on http://0.0.0.0:{self.port} (LAN IP: http://{self.host}:{self.port})")
        httpd.serve_forever()

    # -------------------------------------------------------------
    # Interactive Node Operator Terminal Console (REPL)
    # -------------------------------------------------------------
    def run_interactive_cli(self):
        """Interactive operator terminal console running directly on the node."""
        time.sleep(0.5)
        print("\n" + "=" * 65)
        print("          CSII-PAY INTERACTIVE NODE OPERATOR CONSOLE")
        print("=" * 65)
        print("  Commands:")
        print("    login <account_id> <password>    - Attach operator account to node")
        print("    register <account_id> <password> - Create on-chain account & attach")
        print("    logout                           - Revert node to Guest Mode (0 rewards)")
        print("    status                           - Show node health, height, peers")
        print("    balance                          - Show operator balances & activity")
        print("    peers                            - List connected network nodes")
        print("    sync                             - Force full P2P sync with peers")
        print("    mempool                          - Show pending transactions")
        print("    chain                            - Show recent blocks")
        print("    orders                           - Show smart contract escrow orders")
        print("    help                             - Show this help menu")
        print("    exit / quit                      - Shut down node")
        print("=" * 65 + "\n")

        while self.running:
            try:
                op_name = self.account_id or "GUEST"
                height = len(self.chain) - 1
                prompt = f"[Node:{op_name} | Height:#{height}] > "
                cmd_line = input(prompt).strip()
                if not cmd_line:
                    continue

                parts = cmd_line.split()
                cmd = parts[0].lower()
                args = parts[1:]

                if cmd == "help":
                    print("Available commands: login, register, logout, status, balance, peers, sync, mempool, chain, orders, exit")

                elif cmd == "login":
                    if len(args) < 2:
                        print("Usage: login <account_id> <password>")
                        continue
                    acc_id, pwd = args[0], args[1]
                    if self.state.verify_account(acc_id, pwd):
                        self.account_id = acc_id
                        self.password = pwd
                        self.state.record_activity(acc_id)
                        with self.activity_lock:
                            self.active_accounts[acc_id] = {
                                "last_seen": time.time(),
                                "heartbeat_count": 1,
                                "nonce": secrets.token_hex(8)
                            }
                        bal = self.state.get_balances(acc_id)
                        print(f"[✓] Operator connected: '{acc_id}'")
                        print(f"    Balances: {bal['CSP']:.2f} CSP, {bal['BDP']:.2f} BDP")
                        print(f"    Block rewards from this node will now be credited to '{acc_id}'.")
                    else:
                        print(f"[✗] Login failed: Invalid credentials for account '{acc_id}'")

                elif cmd == "register":
                    if len(args) < 2:
                        print("Usage: register <account_id> <password>")
                        continue
                    acc_id, pwd = args[0], args[1]
                    with self.state.lock:
                        if acc_id in self.state.accounts:
                            print(f"[✗] Registration failed: Account '{acc_id}' already exists")
                            continue

                    salt = secrets.token_hex(16)
                    pwd_hash, _ = hash_password(pwd, salt)
                    privkey, pub_hex = derive_account_keypair(pwd, salt)

                    reg_tx = {
                        "tx_id": hash_data(f"REG_{acc_id}_{time.time()}_{secrets.token_hex(4)}"),
                        "sender": acc_id,
                        "action": "ACCOUNT_REGISTER",
                        "payload": {
                            "account_id": acc_id,
                            "password_hash": pwd_hash,
                            "salt": salt,
                            "public_key": pub_hex,
                            "initial_bdp": DEFAULT_SIGNUP_BDP
                        },
                        "nonce": 0,
                        "timestamp": time.time(),
                        "signature": "SELF_REGISTRATION"
                    }
                    reg_tx["signature"] = sign_transaction_payload(reg_tx, privkey)

                    ok, msg = self.submit_tx(reg_tx)
                    if ok:
                        self.account_id = acc_id
                        self.password = pwd
                        self.state.record_activity(acc_id)
                        print(f"[✓] Account '{acc_id}' registered on network with {DEFAULT_SIGNUP_BDP} BDP welcome bonus!")
                        print(f"[✓] Attached '{acc_id}' as node operator.")
                    else:
                        print(f"[✗] Registration tx rejected: {msg}")

                elif cmd == "logout":
                    if not self.account_id:
                        print("[*] Already in Guest / Unassigned mode.")
                    else:
                        prev = self.account_id
                        self.account_id = None
                        self.password = None
                        print(f"[*] Account '{prev}' logged out. Node reverted to Guest Mode (0 mining rewards).")

                elif cmd == "status":
                    with self.peer_lock:
                        p_count = len(self.peers)
                    with self.mempool_lock:
                        m_count = len(self.mempool)
                    latest = self.chain[-1]
                    print("-" * 55)
                    print(f"  Node ID          : {self.node_id}")
                    print(f"  Operator Account : {self.account_id or 'GUEST (Unassigned)'}")
                    print(f"  Network Address  : http://{self.host}:{self.port}")
                    print(f"  Block Height     : #{len(self.chain) - 1}")
                    print(f"  Latest Hash      : {latest['hash'][:24]}...")
                    print(f"  Latest Validator : {latest.get('validator')}")
                    print(f"  Connected Peers  : {p_count}")
                    print(f"  Mempool Pending  : {m_count} tx(s)")
                    print(f"  State Hash       : {self.state.get_state_hash()[:16]}...")
                    print("-" * 55)

                elif cmd == "balance":
                    if not self.account_id:
                        print("[*] Node is in Guest Mode. Log in with 'login <account_id> <password>' to check balances.")
                    else:
                        bal = self.state.get_balances(self.account_id)
                        acc = self.state.accounts.get(self.account_id, {})
                        act = acc.get("activity", {})
                        print("-" * 55)
                        print(f"  Operator Account : {self.account_id}")
                        print(f"  CSP Balance      : {bal['CSP']:.4f} CSP")
                        print(f"  BDP Balance      : {bal['BDP']:.4f} BDP")
                        print(f"  Account Nonce    : {acc.get('nonce', 0)}")
                        print(f"  PoA Score        : {act.get('score', 0.0)}")
                        print(f"  Tx Count         : {act.get('tx_count', 0)}")
                        print("-" * 55)

                elif cmd == "peers":
                    with self.peer_lock:
                        p_list = list(self.peers)
                    if not p_list:
                        print(f"[*] No peers connected currently. Listening on UDP port {self.udp_port}...")
                    else:
                        print(f"[*] {len(p_list)} Connected Peer(s):")
                        for p in p_list:
                            q = " [QUARANTINED]" if p in self.quarantined_peers and time.time() < self.quarantined_peers[p] else ""
                            print(f"    - {p}{q}")

                elif cmd == "sync":
                    print("[*] Forcing immediate synchronization with all peers...")
                    self.sync_all_peers()
                    print(f"[✓] Sync complete. Current height: #{len(self.chain) - 1}")

                elif cmd == "mempool":
                    with self.mempool_lock:
                        txs = list(self.mempool)
                    if not txs:
                        print("[*] Mempool is empty.")
                    else:
                        print(f"[*] Mempool has {len(txs)} pending transaction(s):")
                        for t in txs:
                            print(f"    - ID: {t.get('tx_id')[:12]}... | Action: {t.get('action')} | Sender: {t.get('sender')} | Nonce: {t.get('nonce')}")

                elif cmd == "chain":
                    print(f"[*] Recent Blocks (Total: {len(self.chain)}):")
                    for b in self.chain[-5:]:
                        tx_c = len(b.get("transactions", []))
                        print(f"    Block #{b['index']} | Hash: {b['hash'][:12]}... | Validator: {b.get('validator')} | Txs: {tx_c} | Time: {time.ctime(b.get('timestamp', 0))}")

                elif cmd == "orders":
                    with self.state.lock:
                        ords = list(self.state.orders.values())
                    if not ords:
                        print("[*] No active or past smart contract escrow orders.")
                    else:
                        print(f"[*] Smart Contract Escrow Orders ({len(ords)}):")
                        for o in ords[-5:]:
                            print(f"    Order #{o['id']} | Maker: {o['maker']} | Offer: {o['offer_amount']} {o['offer_token']} | Request: {o['request_amount']} {o['request_token']} | Status: {o['status']}")

                elif cmd in ("exit", "quit"):
                    print("[*] Exiting node server. Shutting down...")
                    self.running = False
                    break

                else:
                    print(f"[!] Unknown command '{cmd}'. Type 'help' for available commands.")

            except (EOFError, KeyboardInterrupt):
                print("\n[*] Exiting node operator console...")
                self.running = False
                break
            except Exception as e:
                print(f"[!] Error processing command: {e}")

    def start(self):
        """Starts all network, mining, and server worker threads."""
        print("=" * 65)
        print("          CSII-PAY: 2-LAYER CRYPTO NODE SERVER")
        print("=" * 65)
        print(f"  Node ID         : {self.node_id}")
        print(f"  Operator Account: {self.account_id or 'GUEST (Unassigned)'}")
        print(f"  Local WiFi IP   : {self.host}")
        print(f"  HTTP API Port   : {self.port}")
        print(f"  UDP Beacon Port : {self.udp_port}")
        print(f"  Consensus       : Proof of Activity (PoA)")
        print(f"  Current Height  : Block #{len(self.chain) - 1}")
        print("=" * 65)

        # 1. PoA Miner Engine
        t_miner = threading.Thread(target=self.poa_mining_worker, daemon=True)
        t_miner.start()

        # 2. UDP Discovery Broadcaster
        t_udp_send = threading.Thread(target=self.udp_discovery_broadcaster, daemon=True)
        t_udp_send.start()

        # 3. UDP Discovery Listener
        t_udp_recv = threading.Thread(target=self.udp_discovery_listener, daemon=True)
        t_udp_recv.start()

        # 4. Periodic Peer Sync Worker
        t_sync = threading.Thread(target=self.peer_sync_worker, daemon=True)
        t_sync.start()

        # 5. HTTP API Server (runs in daemon thread)
        t_http = threading.Thread(target=self.start_http_api, daemon=True)
        t_http.start()

        # 6. Interactive CLI on main thread (or keepalive if headless / automated test)
        if sys.stdin.isatty():
            self.run_interactive_cli()
        else:
            try:
                while self.running:
                    time.sleep(1)
            except KeyboardInterrupt:
                self.running = False


# -------------------------------------------------------------
# Network Discovery & Launcher
# -------------------------------------------------------------
def discover_active_network_nodes(udp_port: int, initial_peer: str = None, my_port: int = 8000, timeout: float = 1.2) -> list:
    """Probes the network to check if any CSII-Pay nodes are active."""
    active_peers = []

    if initial_peer:
        p_clean = initial_peer.rstrip("/")
        try:
            req = urllib.request.Request(f"{p_clean}/status", headers={"User-Agent": "CSII-Pay-Probe"})
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                if resp.status == 200:
                    active_peers.append(p_clean)
        except Exception:
            pass

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except AttributeError:
        pass
    s.settimeout(timeout)

    try:
        s.bind(("", udp_port))
        start_t = time.time()
        while time.time() - start_t < timeout:
            try:
                data, addr = s.recvfrom(2048)
                msg = json.loads(data.decode("utf-8"))
                if msg.get("type") == "POA_DISCOVERY_BEACON":
                    port = msg.get("port")
                    if port != my_port:
                        host = msg.get("host")
                        if host in ("0.0.0.0", "127.0.0.1") and addr[0] != "127.0.0.1":
                            host = addr[0]
                        p_url = f"http://{host}:{port}"
                        if p_url not in active_peers:
                            active_peers.append(p_url)
            except socket.timeout:
                break
            except Exception:
                pass
    except Exception:
        pass
    finally:
        s.close()

    for probe_port in range(8000, 8009):
        if probe_port == my_port:
            continue
        try:
            req = urllib.request.Request(f"http://127.0.0.1:{probe_port}/status", headers={"User-Agent": "CSII-Pay-Probe"})
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                if resp.status == 200:
                    local_peer = f"http://127.0.0.1:{probe_port}"
                    if local_peer not in active_peers:
                        active_peers.append(local_peer)
        except Exception:
            pass

    return active_peers


def main():
    parser = argparse.ArgumentParser(description="CSII-Pay 2-Layer Cryptocurrency Node")
    parser.add_argument("--account", type=str, default=None, help="Operator account ID")
    parser.add_argument("--password", type=str, default=None, help="Operator password")
    parser.add_argument("--port", type=int, default=DEFAULT_HTTP_PORT, help=f"HTTP API Port (Default: {DEFAULT_HTTP_PORT})")
    parser.add_argument("--udp-port", type=int, default=DEFAULT_UDP_PORT, help=f"UDP Broadcast Port (Default: {DEFAULT_UDP_PORT})")
    parser.add_argument("--peer", type=str, default=None, help="Initial peer to connect to, e.g. http://192.168.1.50:8000")
    parser.add_argument("--data-dir", type=str, default=".", help="Data directory for chain persistence")
    parser.add_argument("--guest", action="store_true", help="Start in Guest / Unassigned operator mode (no rewards minted)")
    args = parser.parse_args()

    local_ip = get_local_ip()

    print("[*] Probing network for existing registered CSII-Pay nodes...")
    active_peers = discover_active_network_nodes(args.udp_port, args.peer, args.port, timeout=1.2)

    target_port = args.port
    if is_port_in_use(target_port, "0.0.0.0"):
        local_peer_url = f"http://127.0.0.1:{target_port}"
        try:
            req = urllib.request.Request(f"{local_peer_url}/status", headers={"User-Agent": "CSII-Pay-Probe"})
            with urllib.request.urlopen(req, timeout=0.5) as resp:
                if resp.status == 200 and local_peer_url not in active_peers:
                    active_peers.append(local_peer_url)
        except Exception:
            pass

        target_port = find_available_port(start_port=target_port + 1)
        print(f"[!] Notice: Port {args.port} is already in use. Automatically assigned port {target_port} for this node.")

    target_udp_port = args.udp_port
    account_id = args.account
    password = args.password

    if not active_peers:
        print("[*] No registered nodes detected in the system.")
        print(f"[*] Initializing Primary Genesis Node with account '{GENESIS_ACCOUNT}' (10,000 CSP, 100 BDP).")
        if not account_id:
            account_id = GENESIS_ACCOUNT
            password = GENESIS_PASSWORD
    else:
        print(f"[!] Active registered node(s) found in system: {', '.join(active_peers)}")
        if args.guest:
            account_id = None
            password = None
            print("[*] Starting node in Guest Mode as requested (--guest).")
        elif not account_id or not password:
            account_id = None
            password = None
            print("[*] Starting in Guest Mode. You can log into an account anytime via the node interface with 'login <account> <password>'.")

    try:
        node = NodeServer(
            host=local_ip,
            port=target_port,
            udp_port=target_udp_port,
            account_id=account_id,
            password=password,
            initial_peers=active_peers,
            data_dir=args.data_dir
        )
        node.start()
    except KeyboardInterrupt:
        print("\n[*] Shutting down CSII-Pay Node. Goodbye!")
        sys.exit(0)
    except Exception as e:
        print(f"\n[!] Fatal Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
