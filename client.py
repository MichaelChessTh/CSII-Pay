#!/usr/bin/env python3
"""
CSII-Pay: 2-Layer Cryptocurrency Client & Wallet (client.py)
-----------------------------------------------------------
Features:
- Connects to CSII-Pay nodes across WiFi (local IP)
- Automatic LAN/WiFi node discovery via UDP beacon listener
- Layer 1 (Base Token: CSP) and Layer 2 (Token on top: BDP) wallet
- Built-in Smart Contract P2P Escrow Order Book (Order creation, fulfillment, cancellation)
- Proof of Activity (PoA) background miner / heartbeat contributor
- Blockchain explorer & account audit
"""

import argparse
import hashlib
import json
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.request

from node import derive_account_keypair, sign_transaction_payload

# ANSI Colors for UI
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[92m"
CYAN = "\033[96m"
YELLOW = "\033[93m"
RED = "\033[91m"
MAGENTA = "\033[95m"
DIM = "\033[2m"

DEFAULT_UDP_PORT = 50555

def calculate_commission(token: str, amount: float) -> float:
    """
    Commission rules:
    - 1% on every BDP transaction.
    - CSP:
      - amount > 500 CSP: 2% commission
      - amount > 150 CSP and <= 500 CSP: 1% commission
      - amount <= 150 CSP: 0% commission (free)
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

def hash_data(data) -> str:
    """Compute deterministic SHA-256 hash."""
    if isinstance(data, (dict, list)):
        serialized = json.dumps(data, sort_keys=True, separators=(",", ":"))
    else:
        serialized = str(data)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()

def get_local_ip() -> str:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = "127.0.0.1"
    finally:
        s.close()
    return ip

def discover_lan_nodes(timeout: float = 3.0, udp_port: int = DEFAULT_UDP_PORT) -> list:
    """Listen for UDP discovery beacons sent by nodes over WiFi LAN."""
    nodes = {}
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
    except AttributeError:
        pass
    s.settimeout(timeout)

    try:
        s.bind(("", udp_port))
    except Exception:
        return []

    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            data, addr = s.recvfrom(2048)
            msg = json.loads(data.decode("utf-8"))
            if msg.get("type") == "POA_DISCOVERY_BEACON":
                host = msg.get("host")
                if host in ("0.0.0.0", "127.0.0.1") and addr[0] != "127.0.0.1":
                    host = addr[0]
                port = msg.get("port")
                url = f"http://{host}:{port}"
                nodes[url] = {
                    "url": url,
                    "account": msg.get("account"),
                    "height": msg.get("chain_length", 0),
                    "node_id": msg.get("node_id")
                }
        except socket.timeout:
            break
        except Exception:
            pass
    s.close()
    return list(nodes.values())


class CryptoClient:
    def __init__(self, node_url: str):
        self.node_url = node_url.rstrip("/")
        self.account_id = None
        self.password = None
        self.privkey = None
        self.pubkey = None
        self.salt = None
        self.token = None
        self.balances = {"CSP": 0.0, "BDP": 0.0}
        self.nonce = 0
        self.activity = {}
        self.poa_mining = False
        self.poa_thread = None
        self.poa_score = 0

    def api_request(self, endpoint: str, method: str = "GET", data: dict = None) -> tuple[bool, dict]:
        url = f"{self.node_url}{endpoint}"
        req_data = json.dumps(data).encode("utf-8") if data else None
        headers = {"Content-Type": "application/json", "User-Agent": "CSII-Pay-Client"}
        req = urllib.request.Request(url, data=req_data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                res_body = resp.read().decode("utf-8")
                return True, json.loads(res_body)
        except urllib.error.HTTPError as e:
            try:
                err_json = json.loads(e.read().decode("utf-8"))
                return False, err_json
            except Exception:
                return False, {"error": f"HTTP {e.code}: {e.reason}"}
        except Exception as e:
            return False, {"error": str(e)}

    def check_node_connection(self) -> tuple[bool, dict]:
        return self.api_request("/status")

    def login(self, account_id: str, password: str) -> tuple[bool, str]:
        ok, res = self.api_request("/login", method="POST", data={"account_id": account_id, "password": password})
        if ok and res.get("success"):
            self.account_id = account_id
            self.password = password
            self.token = res.get("token")
            self.balances = res.get("balances", {"CSP": 0.0, "BDP": 0.0})
            self.nonce = res.get("nonce", 0)
            self.salt = res.get("salt")
            self.pubkey = res.get("public_key")
            if self.salt:
                self.privkey, derived_pub = derive_account_keypair(password, self.salt)
                if not self.pubkey:
                    self.pubkey = derived_pub
            self.start_poa_miner()
            return True, "Login successful"
        return False, res.get("error", "Authentication failed")

    def register(self, account_id: str, password: str) -> tuple[bool, str]:
        ok, res = self.api_request("/register", method="POST", data={"account_id": account_id, "password": password})
        if ok and res.get("success"):
            self.account_id = account_id
            self.password = password
            self.token = res.get("token")
            self.balances = res.get("balances", {"CSP": 0.0, "BDP": 0.0})
            self.nonce = res.get("nonce", 0)
            self.salt = res.get("salt")
            self.pubkey = res.get("public_key")
            if self.salt:
                self.privkey, _ = derive_account_keypair(password, self.salt)
            self.start_poa_miner()
            return True, "Registration successful"
        return False, res.get("error", "Registration failed")

    def refresh_account_data(self):
        if not self.account_id:
            return
        ok, res = self.api_request(f"/account/{self.account_id}")
        if ok:
            self.balances = res.get("balances", self.balances)
            self.nonce = res.get("nonce", self.nonce)
            self.activity = res.get("activity", {})
            self.poa_score = self.activity.get("score", res.get("poa_score", self.poa_score))
            if not self.salt:
                self.salt = res.get("salt")
                if self.salt and self.password:
                    self.privkey, self.pubkey = derive_account_keypair(self.password, self.salt)

    def start_poa_miner(self):
        """Proof of Activity (PoA) heartbeat thread."""
        if self.poa_mining:
            return
        self.poa_mining = True

        def loop():
            while self.poa_mining:
                if self.account_id and self.token:
                    ok, res = self.api_request("/activity/ping", method="POST", data={
                        "account_id": self.account_id,
                        "token": self.token
                    })
                    if ok:
                        self.poa_score = res.get("proof", {}).get("score", self.poa_score)
                time.sleep(5)

        self.poa_thread = threading.Thread(target=loop, daemon=True)
        self.poa_thread.start()

    def stop_poa_miner(self):
        self.poa_mining = False

    def transfer(self, recipient: str, token: str, amount: float) -> tuple[bool, str]:
        """Transfer Layer-1 CSP or Layer-2 BDP with cryptographic signature."""
        self.refresh_account_data()
        tx = {
            "tx_id": hash_data(f"TX_{self.account_id}_{time.time()}_{secrets.token_hex(4)}"),
            "sender": self.account_id,
            "action": "TRANSFER",
            "payload": {
                "recipient": recipient,
                "token": token,
                "amount": float(amount)
            },
            "nonce": self.nonce,
            "timestamp": time.time(),
            "signature": ""
        }
        if self.privkey:
            tx["signature"] = sign_transaction_payload(tx, self.privkey)
        else:
            tx["signature"] = f"SIG_{self.token[:8] if self.token else 'DIRECT'}"

        ok, res = self.api_request("/tx/submit", method="POST", data=tx)
        if ok and res.get("success"):
            self.nonce += 1
            return True, f"Transfer transaction submitted: ID {tx['tx_id'][:12]}..."
        return False, res.get("error", "Transfer failed")

    # -------------------------------------------------------------
    # Smart Contract P2P Order Exchange Actions
    # -------------------------------------------------------------
    def get_orders(self) -> list:
        ok, res = self.api_request("/orders")
        if ok:
            return res.get("orders", [])
        return []

    def create_order(self, offer_token: str, offer_amount: float, request_token: str, request_amount: float, allow_partial: bool = True) -> tuple[bool, str]:
        """Locks offered tokens in smart contract escrow for order-based P2P exchange."""
        self.refresh_account_data()
        order_id = hash_data(f"ORD_{self.account_id}_{time.time()}_{secrets.token_hex(4)}")[:16]
        tx = {
            "tx_id": hash_data(f"TX_ORD_CREATE_{order_id}"),
            "sender": self.account_id,
            "action": "ORDER_CREATE",
            "payload": {
                "order_id": order_id,
                "offer_token": offer_token,
                "offer_amount": float(offer_amount),
                "request_token": request_token,
                "request_amount": float(request_amount),
                "allow_partial": allow_partial
            },
            "nonce": self.nonce,
            "timestamp": time.time(),
            "signature": ""
        }
        if self.privkey:
            tx["signature"] = sign_transaction_payload(tx, self.privkey)
        else:
            tx["signature"] = f"SIG_{self.token[:8] if self.token else 'DIRECT'}"

        ok, res = self.api_request("/tx/submit", method="POST", data=tx)
        if ok and res.get("success"):
            self.nonce += 1
            part_desc = "partial fills allowed" if allow_partial else "full fill only"
            return True, f"Order #{order_id} created ({part_desc})! Escrow deposit of {offer_amount} {offer_token} locked."
        return False, res.get("error", "Order creation failed")

    def fulfill_order(self, order_id: str, fill_amount: float = None) -> tuple[bool, str]:
        """Fulfills an open smart contract order via atomic swap (full or partial)."""
        self.refresh_account_data()
        payload = {"order_id": order_id}
        if fill_amount is not None:
            payload["fill_amount"] = float(fill_amount)

        tx = {
            "tx_id": hash_data(f"TX_ORD_FULFILL_{order_id}_{time.time()}_{secrets.token_hex(2)}"),
            "sender": self.account_id,
            "action": "ORDER_FULFILL",
            "payload": payload,
            "nonce": self.nonce,
            "timestamp": time.time(),
            "signature": ""
        }
        if self.privkey:
            tx["signature"] = sign_transaction_payload(tx, self.privkey)
        else:
            tx["signature"] = f"SIG_{self.token[:8] if self.token else 'DIRECT'}"

        ok, res = self.api_request("/tx/submit", method="POST", data=tx)
        if ok and res.get("success"):
            self.nonce += 1
            return True, f"Order #{order_id} settlement submitted for atomic swap inclusion!"
        return False, res.get("error", "Order fulfillment failed")

    def connect_node_operator(self, account_id: str, password: str) -> tuple[bool, str]:
        """Attaches account as operator on connected node to receive mining rewards."""
        ok, res = self.api_request("/operator/login", method="POST", data={
            "account_id": account_id,
            "password": password
        })
        if ok and res.get("success"):
            return True, res.get("message", "Operator connected")
        return False, res.get("error", "Failed to attach operator account")

    def cancel_order(self, order_id: str) -> tuple[bool, str]:
        """Cancels an open order and refunds escrow deposit."""
        self.refresh_account_data()
        tx = {
            "tx_id": hash_data(f"TX_ORD_CANCEL_{order_id}_{time.time()}"),
            "sender": self.account_id,
            "action": "ORDER_CANCEL",
            "payload": {
                "order_id": order_id
            },
            "nonce": self.nonce,
            "timestamp": time.time(),
            "signature": ""
        }
        if self.privkey:
            tx["signature"] = sign_transaction_payload(tx, self.privkey)
        else:
            tx["signature"] = f"SIG_{self.token[:8] if self.token else 'DIRECT'}"

        ok, res = self.api_request("/tx/submit", method="POST", data=tx)
        if ok and res.get("success"):
            self.nonce += 1
            return True, f"Order #{order_id} cancellation submitted. Escrow will be refunded upon block inclusion."
        return False, res.get("error", "Order cancellation failed")



# -------------------------------------------------------------
# Terminal UI & Interactive CLI
# -------------------------------------------------------------
def clear_banner(client: CryptoClient = None):
    print("\n" + "=" * 68)
    print(f"{BOLD}{CYAN}             CSII-PAY: 2-LAYER CRYPTO CLIENT & WALLET{RESET}")
    print("=" * 68)
    if client:
        client.refresh_account_data()
        act = getattr(client, "activity", {})
        tx_count = act.get("tx_count", 0)
        score = act.get("score", client.poa_score)
        poa_status = f"{GREEN}ACTIVE (Activity Score: {score}, Txs: {tx_count}){RESET}" if client.poa_mining else f"{YELLOW}OFF (Activity Score: {score}, Txs: {tx_count}){RESET}"
        print(f" Connected Node : {CYAN}{client.node_url}{RESET}")
        if client.account_id:
            print(f" Account ID     : {BOLD}{client.account_id}{RESET}")
            print(f" Balances       : {GREEN}{client.balances.get('CSP', 0.0):,.4f} CSP{RESET} (L1 Base) | {MAGENTA}{client.balances.get('BDP', 0.0):,.4f} BDP{RESET} (L2 Asset)")
            print(f" Activity Stats : {poa_status}")
        else:
            print(f" Status         : {YELLOW}Not Logged In{RESET}")
    print("-" * 68)

def prompt_select_node() -> str:
    local_ip = get_local_ip()
    print(f"\n[*] Local WiFi / LAN IP detected: {BOLD}{local_ip}{RESET}")
    print("[*] Scanning WiFi network for active CSII-Pay nodes (UDP beacon)...")
    nodes = discover_lan_nodes(timeout=2.0)

    print("\nAvailable Connection Options:")
    options = []
    if nodes:
        for i, n in enumerate(nodes):
            print(f"  [{i + 1}] Discovered Node: {GREEN}{n['url']}{RESET} (Operator: {n['account']}, Height: #{n['height']})")
            options.append(n['url'])
    else:
        print(f"  {DIM}(No broadcast nodes found on LAN broadcast yet){RESET}")

    default_local = f"http://127.0.0.1:8000"
    default_lan = f"http://{local_ip}:8000"
    print(f"  [L] Localhost Default ({default_local})")
    print(f"  [W] Local WiFi Default ({default_lan})")
    print(f"  [M] Enter Custom IP & Port manually")

    choice = input(f"\nSelect node option: ").strip().lower()
    if choice.isdigit() and 1 <= int(choice) <= len(options):
        return options[int(choice) - 1]
    elif choice == "w":
        return default_lan
    elif choice == "m":
        custom = input("Enter Node URL (e.g. http://192.168.1.100:8000): ").strip()
        if not custom.startswith("http"):
            custom = "http://" + custom
        return custom
    else:
        return default_local

def login_flow(client: CryptoClient):
    while not client.account_id:
        clear_banner(client)
        print(f"{BOLD}ACCOUNT AUTHENTICATION:{RESET}")
        print("  [1] Quick Login as First Node Account (6958082456 / 123)")
        print("  [2] Login with existing account")
        print("  [3] Register new account")
        print("  [4] Change / Switch Node")
        print("  [0] Exit")

        choice = input("\nSelect choice: ").strip()
        if choice == "1":
            ok, msg = client.login("6958082456", "123")
            if ok:
                print(f"{GREEN}[✓] {msg}{RESET}")
                time.sleep(1)
            else:
                print(f"{RED}[✗] {msg}{RESET}")
                input("Press Enter to continue...")
        elif choice == "2":
            acc = input("Enter Account ID: ").strip()
            pwd = input("Enter Password: ").strip()
            ok, msg = client.login(acc, pwd)
            if ok:
                print(f"{GREEN}[✓] {msg}{RESET}")
                time.sleep(1)
            else:
                print(f"{RED}[✗] {msg}{RESET}")
                input("Press Enter to continue...")
        elif choice == "3":
            acc = input("Create Account ID (e.g. 10 digits or username): ").strip()
            pwd = input("Create Password: ").strip()
            ok, msg = client.register(acc, pwd)
            if ok:
                print(f"{GREEN}[✓] Account created! Automatically received 100.0 BDP welcome bonus!{RESET}")
                time.sleep(1.2)
            else:
                print(f"{RED}[✗] {msg}{RESET}")
                input("Press Enter to continue...")
        elif choice == "4":
            new_url = prompt_select_node()
            client.node_url = new_url.rstrip("/")
            ok, res = client.check_node_connection()
            if ok:
                print(f"{GREEN}[✓] Connected to {new_url}{RESET}")
            else:
                print(f"{RED}[✗] Cannot reach {new_url}: {res.get('error')}{RESET}")
            input("Press Enter to continue...")
        elif choice == "0":
            sys.exit(0)

def handle_transfer(client: CryptoClient):
    clear_banner(client)
    print(f"{BOLD}TRANSFER TOKENS:{RESET}")
    print("  [1] Transfer CSP (Layer 1 Base Currency)")
    print("  [2] Transfer BDP (Layer 2 Token)")
    print("  [0] Back to Main Menu")

    choice = input("\nSelect token: ").strip()
    if choice == "1":
        token = "CSP"
    elif choice == "2":
        token = "BDP"
    else:
        return

    recipient = input(f"Recipient Account ID: ").strip()
    if not recipient:
        print(f"{RED}Recipient cannot be empty.{RESET}")
        input("Press Enter to return...")
        return

    try:
        amount = float(input(f"Amount of {token} to send: ").strip())
    except ValueError:
        print(f"{RED}Invalid numerical amount.{RESET}")
        input("Press Enter to return...")
        return

    fee = calculate_commission(token, amount)
    pct = "1%" if token == "BDP" else ("2%" if amount > 500 else ("1%" if amount > 150 else "0% (Free)"))
    total_cost = round(amount + fee, 6)

    print(f"\nTransaction Details:")
    print(f"  Token          : {token}")
    print(f"  Recipient      : {recipient}")
    print(f"  Transfer Amount: {amount:,.4f} {token}")
    print(f"  Network Fee    : {fee:,.4f} {token} ({pct} commission)")
    print(f"  Total to Debit : {total_cost:,.4f} {token}")

    confirm = input(f"\nConfirm transfer of {total_cost} {token}? (y/N): ").strip().lower()
    if confirm != "y":
        print(f"{YELLOW}Transfer cancelled.{RESET}")
        input("Press Enter to return...")
        return

    print(f"\nSending {BOLD}{amount} {token}{RESET} (plus {fee} fee) to {BOLD}{recipient}{RESET}...")
    ok, msg = client.transfer(recipient, token, amount)
    if ok:
        print(f"{GREEN}[✓] {msg}{RESET}")
    else:
        print(f"{RED}[✗] Error: {msg}{RESET}")
    input("\nPress Enter to return to menu...")

def handle_smart_contract_exchange(client: CryptoClient):
    while True:
        clear_banner(client)
        print(f"{BOLD}BUILT-IN SMART CONTRACT: ORDER-BASED P2P EXCHANGE{RESET}")
        print(f"{DIM}Note: Per protocol rules, no automated paygate exists. All swaps execute peer-to-peer via on-chain escrow deposits.{RESET}\n")

        orders = client.get_orders()
        open_orders = [o for o in orders if o.get("status") == "OPEN"]

        print(f"{BOLD}Active Escrow Orders in Market ({len(open_orders)} open):{RESET}")
        if not open_orders:
            print(f"  {DIM}No open orders currently available in the contract order book.{RESET}")
        else:
            print(f"  {'ID':<18} {'Maker':<14} {'Offering (Escrow)':<20} {'Requesting':<20} {'Partial?':<10} {'Rate':<15}")
            print("  " + "-" * 100)
            for o in open_orders:
                off = f"{o['offer_amount']:,.2f} {o['offer_token']}"
                req = f"{o['request_amount']:,.2f} {o['request_token']}"
                rate = f"{o['offer_amount'] / max(0.0001, o['request_amount']):.4f} {o['offer_token']}/{o['request_token']}"
                maker_tag = f"{o['maker']}" + (" (YOU)" if o['maker'] == client.account_id else "")
                part_tag = "YES" if o.get("allow_partial", True) else "NO"
                print(f"  {o['id']:<18} {maker_tag:<14} {off:<20} {req:<20} {part_tag:<10} {rate:<15}")

        print("\nExchange Actions:")
        print("  [1] Create New Order (Deposit funds into Escrow)")
        print("  [2] Fulfill an Order (Accept order & execute Atomic Swap)")
        print("  [3] Cancel My Order (Refund escrowed deposit)")
        print("  [4] View All Order History (Completed / Cancelled)")
        print("  [0] Return to Main Menu")

        choice = input("\nSelect exchange action: ").strip()

        if choice == "1":
            print("\nCreate Escrow Exchange Order:")
            print("  [A] Sell CSP (L1) -> Receive BDP (L2)")
            print("  [B] Sell BDP (L2) -> Receive CSP (L1)")
            pair = input("Select pair (A/B): ").strip().upper()
            if pair == "A":
                off_tok, req_tok = "CSP", "BDP"
            elif pair == "B":
                off_tok, req_tok = "BDP", "CSP"
            else:
                continue

            try:
                off_amt = float(input(f"Deposit amount of {off_tok} to lock in escrow: ").strip())
                req_amt = float(input(f"Target amount of {req_tok} you want in return: ").strip())
            except ValueError:
                print(f"{RED}Invalid numerical amount.{RESET}")
                input("Press Enter to continue...")
                continue

            partial_in = input("Allow partial fulfillment? [Y/n] (Default: Yes): ").strip().lower()
            allow_partial = False if partial_in == "n" else True

            ok, msg = client.create_order(off_tok, off_amt, req_tok, req_amt, allow_partial=allow_partial)
            if ok:
                print(f"{GREEN}[✓] {msg}{RESET}")
            else:
                print(f"{RED}[✗] {msg}{RESET}")
            input("Press Enter to continue...")

        elif choice == "2":
            order_id = input("\nEnter Order ID to fulfill (Atomic Swap): ").strip()
            target_order = next((o for o in open_orders if o['id'] == order_id), None)
            if not target_order:
                print(f"{RED}Order ID not found in open orders.{RESET}")
                input("Press Enter to continue...")
                continue

            if target_order["maker"] == client.account_id:
                print(f"{YELLOW}You cannot fulfill your own order. Use Cancel if you want your deposit back.{RESET}")
                input("Press Enter to continue...")
                continue

            fill_amt = None
            req_cost = target_order['request_amount']
            take_display = target_order['offer_amount']

            if target_order.get("allow_partial", True):
                print(f"\nOrder allows partial conducting (Available: {target_order['offer_amount']} {target_order['offer_token']}).")
                amt_str = input(f"Amount of {target_order['offer_token']} to take (Press Enter for 100%): ").strip()
                if amt_str:
                    try:
                        fill_amt = float(amt_str)
                        if fill_amt <= 0 or fill_amt > target_order['offer_amount']:
                            print(f"{RED}Amount must be between 0 and {target_order['offer_amount']}.{RESET}")
                            input("Press Enter to continue...")
                            continue
                        ratio = fill_amt / target_order['offer_amount']
                        req_cost = round(target_order['request_amount'] * ratio, 6)
                        take_display = fill_amt
                    except ValueError:
                        print(f"{RED}Invalid numerical amount.{RESET}")
                        input("Press Enter to continue...")
                        continue

            print(f"Confirm Atomic Swap: You will deposit {BOLD}{req_cost} {target_order['request_token']}{RESET} and receive {BOLD}{take_display} {target_order['offer_token']}{RESET}.")
            confirm = input("Confirm swap? (y/N): ").strip().lower()
            if confirm == "y":
                ok, msg = client.fulfill_order(order_id, fill_amount=fill_amt)
                if ok:
                    print(f"{GREEN}[✓] {msg}{RESET}")
                else:
                    print(f"{RED}[✗] {msg}{RESET}")
            input("Press Enter to continue...")

        elif choice == "3":
            my_orders = [o for o in open_orders if o['maker'] == client.account_id]
            if not my_orders:
                print(f"{YELLOW}You have no active open orders to cancel.{RESET}")
                input("Press Enter to continue...")
                continue

            order_id = input("\nEnter your Order ID to cancel & refund: ").strip()
            ok, msg = client.cancel_order(order_id)
            if ok:
                print(f"{GREEN}[✓] {msg}{RESET}")
            else:
                print(f"{RED}[✗] {msg}{RESET}")
            input("Press Enter to continue...")

        elif choice == "4":
            print("\nOrder Book History:")
            for o in orders:
                st = o.get("status")
                st_color = GREEN if st == "COMPLETED" else (RED if st == "CANCELLED" else YELLOW)
                print(f"  Order #{o['id']} | Maker: {o['maker']} | {o['offer_amount']} {o['offer_token']} -> {o['request_amount']} {o['request_token']} | Status: {st_color}{st}{RESET}")
            input("\nPress Enter to continue...")

        elif choice == "0":
            break

def view_blockchain_explorer(client: CryptoClient):
    clear_banner(client)
    print(f"{BOLD}BLOCKCHAIN EXPLORER & NETWORK STATUS{RESET}\n")
    ok, res = client.api_request("/status")
    if ok:
        print(f"  Block Height    : #{res.get('block_height')}")
        print(f"  Latest Hash     : {res.get('latest_block_hash')}")
        print(f"  Connected Peers : {res.get('peers_count')}")
        print(f"  Mempool Size    : {res.get('mempool_size')} pending transactions")
        print(f"  Active Accounts : {res.get('active_users_count')} (PoA participating)")
        print(f"  Consensus       : {res.get('consensus')}")
    else:
        print(f"{RED}Failed to fetch status: {res.get('error')}{RESET}")

    ok, chain_res = client.api_request("/chain")
    if ok:
        chain = chain_res.get("chain", [])
        print(f"\n{BOLD}Recent Blocks (Total {len(chain)}):{RESET}")
        for b in chain[-5:]:
            print(f"  Block #{b['index']} | Hash: {CYAN}{b['hash'][:12]}...{RESET} | Validator: {b['validator']} | Txs: {len(b['transactions'])} | PoA Proofs: {len(b['activity_proofs'])}")
    input("\nPress Enter to return to menu...")

def main():
    parser = argparse.ArgumentParser(description="CSII-Pay Cryptocurrency Client & Wallet")
    parser.add_argument("--node", type=str, default=None, help="Node URL (e.g. http://192.168.1.100:8000)")
    parser.add_argument("--account", type=str, default=None, help="Auto-login account ID")
    parser.add_argument("--password", type=str, default=None, help="Auto-login password")
    args = parser.parse_args()

    node_url = args.node
    if not node_url:
        node_url = prompt_select_node()

    client = CryptoClient(node_url)

    # Verify node connection
    ok, res = client.check_node_connection()
    if not ok:
        print(f"{RED}[!] Error: Could not connect to node at {node_url}: {res.get('error')}{RESET}")
        print("[*] Make sure node.py is running on that host/port.")
        sys.exit(1)

    print(f"{GREEN}[✓] Connected to CSII-Pay node at {node_url}!{RESET}")

    # Auto-login if provided via flags
    if args.account and args.password:
        client.login(args.account, args.password)

    # Enter login flow if not authenticated
    login_flow(client)

    # Main Interactive Menu Loop
    while True:
        clear_banner(client)
        print(f"{BOLD}MAIN MENU:{RESET}")
        print("  [1] Refresh Balances & Activity Status")
        print("  [2] Transfer Tokens (CSP L1 / BDP L2)")
        print("  [3] Smart Contract P2P Escrow Exchange (Buy/Sell CSP & BDP)")
        print("  [4] Toggle PoA Activity Miner Heartbeat")
        print("  [5] Blockchain Explorer & Network Peers")
        print("  [6] Switch Node")
        print("  [0] Exit")

        choice = input("\nSelect option: ").strip()

        if choice == "1":
            client.refresh_account_data()
            time.sleep(0.3)
        elif choice == "2":
            handle_transfer(client)
        elif choice == "3":
            handle_smart_contract_exchange(client)
        elif choice == "4":
            if client.poa_mining:
                client.stop_poa_miner()
                print(f"{YELLOW}[*] PoA activity miner stopped.{RESET}")
            else:
                client.start_poa_miner()
                print(f"{GREEN}[*] PoA activity miner activated! Sending periodic signed activity proofs.{RESET}")
            time.sleep(1)
        elif choice == "5":
            view_blockchain_explorer(client)
        elif choice == "6":
            new_url = prompt_select_node()
            client.node_url = new_url.rstrip("/")
            ok, res = client.check_node_connection()
            if ok:
                print(f"{GREEN}[✓] Connected to {new_url}{RESET}")
            else:
                print(f"{RED}[✗] Cannot reach {new_url}: {res.get('error')}{RESET}")
            time.sleep(1)
        elif choice == "0":
            print("\n[*] Exiting CSII-Pay Client. Goodbye!")
            client.stop_poa_miner()
            sys.exit(0)

if __name__ == "__main__":
    main()
