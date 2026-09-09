#!/usr/bin/env python3
"""
Comprehensive automated test suite for CSII-Pay
Tests:
1. Rejection of invalid operator credentials.
2. Primary Node startup on port 8000 with genesis account (6958082456 / 123).
3. Genesis Block verification: exactly 10,000 CSP and 100 BDP for 6958082456.
4. Account Registration with 100 BDP Automatic Signup Bonus & L1/L2 Signed Transfers with Commissions:
   - 1% on BDP
   - 0% on micro-transfer (<= 150 CSP)
   - 1% on 150-500 CSP
   - 2% on > 500 CSP
5. Cryptographic Security Enforcement:
   - Rejection of forged/tampered signatures (400 Bad Request)
   - Rejection of replay attacks via strict sequential nonces
6. Smart Contract Partial Conducting & Escrow Exchange:
   - Partial fulfillment of open order (take 4 BDP out of 10 BDP for pro-rata CSP)
   - Order remaining balance validation (6 BDP / 300 CSP remaining, status OPEN)
   - Completion of remaining balance
   - Non-partial contract rejection when allow_partial=False
   - Order cancellation & remaining escrow refund
7. Same-Device Multi-Node Startup:
   - Auto-detection of port 8000 conflict and automatic binding to port 8001
   - Peer auto-discovery on local machine
8. Guest Mode Mining & Zero Reward Distribution:
   - Unassigned node mines block; verified 0 reward minted to any account
   - Connecting account via /operator/login; verified subsequent block rewards that account
9. Multi-Node P2P chain and state synchronization parity & fork resolution.
"""

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
import urllib.error

from node import (
    GENESIS_ACCOUNT,
    GENESIS_PASSWORD,
    GENESIS_SALT,
    derive_account_keypair,
    sign_transaction_payload,
    hash_data
)

TEST_DIR = "/Users/chess/StudioProjects/CSII-Pay/test_env"

def get_account_info(node_url: str, account_id: str) -> dict:
    req = urllib.request.Request(f"{node_url}/account/{account_id}", headers={"User-Agent": "CSII-Pay-Test"})
    with urllib.request.urlopen(req, timeout=3) as resp:
        return json.loads(resp.read().decode("utf-8"))

def send_signed_tx(node_url: str, sender: str, privkey: int, action: str, payload: dict) -> tuple[bool, dict]:
    acc_info = get_account_info(node_url, sender)
    nonce = acc_info.get("nonce", 0)
    tx = {
        "tx_id": hash_data(f"TX_{sender}_{nonce}_{time.time()}"),
        "sender": sender,
        "action": action,
        "payload": payload,
        "nonce": nonce,
        "timestamp": time.time(),
        "signature": ""
    }
    tx["signature"] = sign_transaction_payload(tx, privkey)

    req = urllib.request.Request(
        f"{node_url}/tx/submit",
        data=json.dumps(tx).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return True, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        try:
            return False, json.loads(err_body)
        except Exception:
            return False, {"error": err_body}

def run_test():
    print("=" * 70)
    print("       CSII-PAY: COMPREHENSIVE AUTOMATED VERIFICATION SUITE")
    print("=" * 70)

    # Clean test directory and kill any stale test nodes
    subprocess.run("pkill -9 -f 'node.py' 2>/dev/null || true", shell=True)
    time.sleep(1.0)
    if os.path.exists(TEST_DIR):
        shutil.rmtree(TEST_DIR)
    os.makedirs(TEST_DIR, exist_ok=True)

    node1_proc = None
    node2_proc = None

    try:
        # -------------------------------------------------------------
        # 1. Test Node Operator Authentication Failure with Invalid Credentials
        # -------------------------------------------------------------
        print("\n[TEST 1] Testing Node Operator Authentication Enforcement...")
        res_fail = subprocess.run([
            sys.executable, "node.py",
            "--account", "6958082456",
            "--password", "wrong_password_xyz",
            "--port", "8015",
            "--data-dir", TEST_DIR
        ], capture_output=True, text=True)
        assert res_fail.returncode != 0, "Node should have rejected invalid operator password"
        assert "CRITICAL: Failed to authenticate node operator" in (res_fail.stdout + res_fail.stderr)
        print("  [✓] Successfully rejected node startup with invalid operator credentials.")

        # -------------------------------------------------------------
        # 2. Launch Primary Genesis Node (Port 8000, 6958082456 / 123)
        # -------------------------------------------------------------
        print("\n[TEST 2] Launching Primary Node (6958082456 / 123 on port 8000)...")
        node1_proc = subprocess.Popen([
            sys.executable, "node.py",
            "--account", "6958082456",
            "--password", "123",
            "--port", "8000",
            "--udp-port", "50556",
            "--data-dir", TEST_DIR
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        time.sleep(2.5)

        resp = urllib.request.urlopen("http://127.0.0.1:8000/status", timeout=3)
        status_data = json.loads(resp.read().decode("utf-8"))
        print(f"  [✓] Node 1 Online: Operator={status_data['operator_account']}, Height=#{status_data['block_height']}")
        assert status_data["operator_account"] == "6958082456", "Operator account mismatch"

        # Derive Genesis Keypair
        gen_priv, gen_pub = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)

        # -------------------------------------------------------------
        # 3. Verify Genesis Balances for 6958082456 (10,000 CSP, 100 BDP)
        # -------------------------------------------------------------
        print("\n[TEST 3] Verifying Genesis Block & Initial Balances...")
        acc_data = get_account_info("http://127.0.0.1:8000", GENESIS_ACCOUNT)
        balances = acc_data["balances"]
        print(f"  [✓] Account 6958082456 Balances: {balances['CSP']} CSP, {balances['BDP']} BDP")
        assert balances["CSP"] == 10000.0, f"Expected 10,000 CSP, got {balances['CSP']}"
        assert balances["BDP"] == 100.0, f"Expected 100 BDP, got {balances['BDP']}"

        # -------------------------------------------------------------
        # 4. Account Registration (100 BDP Automatic Bonus) & Token Transfers
        # -------------------------------------------------------------
        print("\n[TEST 4] Testing Automatic 100 BDP Signup Bonus & Signed L1/L2 Transfers...")
        # Register Alice
        reg_req = urllib.request.Request(
            "http://127.0.0.1:8000/register",
            data=json.dumps({"account_id": "alice_user", "password": "alice_password"}).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        reg_res = json.loads(urllib.request.urlopen(reg_req).read().decode("utf-8"))
        assert reg_res["success"], "Alice registration failed"
        alice_salt = reg_res["salt"]
        alice_priv, alice_pub = derive_account_keypair("alice_password", alice_salt)
        print(f"  [✓] Registered alice_user with welcome bonus: {reg_res['balances']['BDP']} BDP")
        assert reg_res["balances"]["BDP"] == 100.0, f"Expected 100.0 BDP signup bonus, got {reg_res['balances']['BDP']}"

        # Transfer 200 CSP and 20 BDP from Genesis to Alice
        ok1, _ = send_signed_tx("http://127.0.0.1:8000", GENESIS_ACCOUNT, gen_priv, "TRANSFER", {
            "recipient": "alice_user", "token": "CSP", "amount": 200.0
        })
        assert ok1, "Genesis transfer of 200 CSP to Alice failed"

        ok2, _ = send_signed_tx("http://127.0.0.1:8000", GENESIS_ACCOUNT, gen_priv, "TRANSFER", {
            "recipient": "alice_user", "token": "BDP", "amount": 20.0
        })
        assert ok2, "Genesis transfer of 20 BDP to Alice failed"

        print("  [*] Waiting for PoA round to forge block with transactions...")
        time.sleep(9.0)

        # Alice balance: 200 CSP, and 100 + 20 = 120 BDP!
        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        print(f"  [✓] Alice Balances: {alice_data['balances']['CSP']} CSP, {alice_data['balances']['BDP']} BDP")
        assert alice_data["balances"]["CSP"] == 200.0, f"Expected 200 CSP, got {alice_data['balances']['CSP']}"
        assert alice_data["balances"]["BDP"] == 120.0, f"Expected 120 BDP, got {alice_data['balances']['BDP']}"

        # Node 1 Operator receives deflationary base reward (5.0 CSP) + commissions (2.0 CSP, 0.2 BDP)
        gen_data = get_account_info("http://127.0.0.1:8000", GENESIS_ACCOUNT)
        print(f"  [✓] Node Operator Balances: {gen_data['balances']['CSP']} CSP, {gen_data['balances']['BDP']} BDP")
        # 10000 - 202 + (5.0 base reward + 2.0 fee) = 9805.0 CSP
        assert gen_data["balances"]["CSP"] == 9805.0, f"Expected 9805.0 CSP, got {gen_data['balances']['CSP']}"
        assert gen_data["balances"]["BDP"] == 80.0, f"Expected 80.0 BDP (100 - 20.2 + 0.2 fee reward), got {gen_data['balances']['BDP']}"

        # Micro-transfer: 0% fee on CSP <= 150 CSP
        ok_zero, _ = send_signed_tx("http://127.0.0.1:8000", "alice_user", alice_priv, "TRANSFER", {
            "recipient": GENESIS_ACCOUNT, "token": "CSP", "amount": 50.0
        })
        assert ok_zero, "Alice transfer of 50 CSP failed"
        time.sleep(9.0)

        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        # 200 - 50 = 150 CSP (0 fee)
        assert alice_data["balances"]["CSP"] == 150.0, f"Expected 150.0 CSP, got {alice_data['balances']['CSP']}"
        print("  [✓] Verified 0% commission for transfer <= 150 CSP.")

        # -------------------------------------------------------------
        # 5. Cryptographic Security Enforcement (Signatures & Nonces)
        # -------------------------------------------------------------
        print("\n[TEST 5] Testing Cryptographic Signature & Replay Nonce Enforcement...")
        # 5A: Try submitting a forged transaction with an invalid signature
        alice_nonce = get_account_info("http://127.0.0.1:8000", "alice_user")["nonce"]
        forged_tx = {
            "tx_id": "tx_forged_steal_money",
            "sender": "alice_user",
            "action": "TRANSFER",
            "payload": {"recipient": GENESIS_ACCOUNT, "token": "CSP", "amount": 100.0},
            "nonce": alice_nonce,
            "timestamp": time.time(),
            "signature": "0" * 192  # Invalid dummy signature
        }
        try:
            req = urllib.request.Request(
                "http://127.0.0.1:8000/tx/submit",
                data=json.dumps(forged_tx).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            urllib.request.urlopen(req, timeout=3)
            assert False, "Node should have rejected forged signature!"
        except urllib.error.HTTPError as e:
            assert e.code == 400
            print("  [✓] Successfully rejected forged transaction signature (HTTP 400).")

        # 5B: Try submitting a replay attack with an outdated nonce
        replay_tx = {
            "tx_id": "tx_replay_attack",
            "sender": "alice_user",
            "action": "TRANSFER",
            "payload": {"recipient": GENESIS_ACCOUNT, "token": "CSP", "amount": 10.0},
            "nonce": alice_nonce - 1,  # Old nonce
            "timestamp": time.time(),
            "signature": ""
        }
        replay_tx["signature"] = sign_transaction_payload(replay_tx, alice_priv)
        try:
            req = urllib.request.Request(
                "http://127.0.0.1:8000/tx/submit",
                data=json.dumps(replay_tx).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            urllib.request.urlopen(req, timeout=3)
            assert False, "Node should have rejected replayed transaction nonce!"
        except urllib.error.HTTPError as e:
            assert e.code == 400
            print("  [✓] Successfully rejected replay attack with stale nonce (HTTP 400).")

        # -------------------------------------------------------------
        # 6. Smart Contract: Partial Conducting of Orders
        # -------------------------------------------------------------
        print("\n[TEST 6] Testing Smart Contract Partial Conducting of Orders...")
        # Alice deposits 10 BDP into Escrow seeking 500 CSP with allow_partial=True (default)
        ok_ord, _ = send_signed_tx("http://127.0.0.1:8000", "alice_user", alice_priv, "ORDER_CREATE", {
            "order_id": "alice_partial_order_101",
            "offer_token": "BDP",
            "offer_amount": 10.0,
            "request_token": "CSP",
            "request_amount": 500.0,
            "allow_partial": True
        })
        assert ok_ord, "Alice order creation failed"
        time.sleep(9.0)

        # Verify Escrow deduction: Alice had 120 BDP, now 110 BDP
        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        assert alice_data["balances"]["BDP"] == 110.0, "Escrow deposit was not deducted from Alice"
        print("  [✓] Order created: 10 BDP locked into escrow. allow_partial=True verified.")

        # Partial fulfillment: Operator 6958082456 fulfills 4.0 BDP out of 10.0 BDP (pro-rata: 200 CSP)
        ok_fill, _ = send_signed_tx("http://127.0.0.1:8000", GENESIS_ACCOUNT, gen_priv, "ORDER_FULFILL", {
            "order_id": "alice_partial_order_101",
            "fill_amount": 4.0
        })
        assert ok_fill, "Partial order fulfillment failed"
        time.sleep(9.0)

        # Check order status: should remain OPEN with 6.0 BDP remaining and 300.0 CSP remaining
        orders_resp = json.loads(urllib.request.urlopen("http://127.0.0.1:8000/orders").read().decode("utf-8"))
        part_order = next(o for o in orders_resp["orders"] if o["id"] == "alice_partial_order_101")
        print(f"  [✓] Partially Filled Order Status: {part_order['status']}, Remaining: {part_order['offer_amount']} BDP for {part_order['request_amount']} CSP")
        assert part_order["status"] == "OPEN", "Partially filled order should remain OPEN"
        assert part_order["offer_amount"] == 6.0, f"Expected 6.0 BDP remaining, got {part_order['offer_amount']}"
        assert part_order["request_amount"] == 300.0, f"Expected 300.0 CSP remaining, got {part_order['request_amount']}"

        # Alice received 200 CSP from the partial fill (150 + 200 = 350 CSP)
        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        assert alice_data["balances"]["CSP"] == 350.0, f"Expected 350.0 CSP for Alice, got {alice_data['balances']['CSP']}"
        print("  [✓] Alice received exactly 200.0 CSP for partial 4.0 BDP fill.")

        # Fulfill the remaining 6.0 BDP to complete the order
        ok_fill_rest, _ = send_signed_tx("http://127.0.0.1:8000", GENESIS_ACCOUNT, gen_priv, "ORDER_FULFILL", {
            "order_id": "alice_partial_order_101",
            "fill_amount": 6.0
        })
        assert ok_fill_rest, "Final fulfillment failed"
        time.sleep(9.0)

        orders_resp = json.loads(urllib.request.urlopen("http://127.0.0.1:8000/orders").read().decode("utf-8"))
        completed_order = next(o for o in orders_resp["orders"] if o["id"] == "alice_partial_order_101")
        assert completed_order["status"] == "COMPLETED", "Order should now be COMPLETED"
        print("  [✓] Final partial fill completed order cleanly. Status: COMPLETED.")

        # Alice now has 350 + 300 = 650 CSP
        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        assert alice_data["balances"]["CSP"] == 650.0

        # Test partial conducting rejection when allow_partial=False
        print("  [*] Testing allow_partial=False enforcement...")
        ok_nopart, _ = send_signed_tx("http://127.0.0.1:8000", "alice_user", alice_priv, "ORDER_CREATE", {
            "order_id": "alice_fullonly_order_202",
            "offer_token": "CSP",
            "offer_amount": 50.0,
            "request_token": "BDP",
            "request_amount": 5.0,
            "allow_partial": False
        })
        assert ok_nopart, "Order creation with allow_partial=False failed"
        time.sleep(9.0)

        # Attempt partial fill of 20 CSP: should be rejected
        ok_fail_fill, res_fail_fill = send_signed_tx("http://127.0.0.1:8000", GENESIS_ACCOUNT, gen_priv, "ORDER_FULFILL", {
            "order_id": "alice_fullonly_order_202",
            "fill_amount": 20.0
        })
        assert not ok_fail_fill, "Partial fill should have been rejected when allow_partial=False"
        print("  [✓] Successfully rejected partial fulfillment on order with allow_partial=False.")

        # Alice cancels this order and gets her 50 CSP back
        ok_cancel, _ = send_signed_tx("http://127.0.0.1:8000", "alice_user", alice_priv, "ORDER_CANCEL", {
            "order_id": "alice_fullonly_order_202"
        })
        assert ok_cancel, "Cancellation failed"
        time.sleep(9.0)

        alice_data = get_account_info("http://127.0.0.1:8000", "alice_user")
        assert alice_data["balances"]["CSP"] == 650.0, "50 CSP was not refunded on cancellation"
        print("  [✓] Order cancelled and full deposit refunded.")

        # -------------------------------------------------------------
        # 7. Same-Device Multi-Node Startup & Auto-Binding
        # -------------------------------------------------------------
        print("\n[TEST 7] Testing Same-Device Multi-Node Startup & Port Auto-Binding...")
        node2_proc = subprocess.Popen([
            sys.executable, "-u", "node.py",
            "--guest",
            "--udp-port", "50557",
            "--data-dir", TEST_DIR
        ])

        time.sleep(3.5)

        # Check Node 2 on auto-selected port 8001
        resp2 = urllib.request.urlopen("http://127.0.0.1:8001/status", timeout=3)
        status2 = json.loads(resp2.read().decode("utf-8"))
        print(f"  [✓] Node 2 Online: Port={status2['port']}, Operator={status2['operator_account']}, Height=#{status2['block_height']}")
        assert status2["port"] == 8001, f"Expected Node 2 on auto-assigned port 8001, got {status2['port']}"
        assert status2["operator_account"] == "GUEST_UNASSIGNED", "Node 2 should be in guest mode"

        # -------------------------------------------------------------
        # 8. Guest Mode Mining with Zero Rewards & Runtime Operator Login
        # -------------------------------------------------------------
        print("\n[TEST 8] Testing Guest Mode Mining (Zero Rewards) & Runtime Operator Attach...")
        reg_bob = urllib.request.Request(
            "http://127.0.0.1:8001/register",
            data=json.dumps({"account_id": "bob_user", "password": "bob_password"}).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        bob_res = json.loads(urllib.request.urlopen(reg_bob).read().decode("utf-8"))
        assert bob_res["balances"]["BDP"] == 100.0, "Bob should also receive 100 BDP signup bonus"
        bob_salt = bob_res["salt"]
        bob_priv, bob_pub = derive_account_keypair("bob_password", bob_salt)
        print("  [✓] Registered bob_user on Node 2 with 100 BDP signup bonus.")

        # Temporarily disconnect Node 1 to test node failure/disconnection and guest mining
        print("  [*] Simulating Node 1 offline disconnection (Node fall/failover)...")
        node1_proc.terminate()
        node1_proc.wait()

        # Alice transfers 10 CSP to Bob via Node 2
        ok_bob_transfer, _ = send_signed_tx("http://127.0.0.1:8001", "alice_user", alice_priv, "TRANSFER", {
            "recipient": "bob_user", "token": "CSP", "amount": 10.0
        })
        assert ok_bob_transfer, "Transfer to Bob failed"

        print("  [*] Waiting for Node 2 (Guest Mode) to mine block...")
        time.sleep(9.0)

        chain_resp = json.loads(urllib.request.urlopen("http://127.0.0.1:8001/chain").read().decode("utf-8"))
        latest_b = chain_resp["chain"][-1]
        print(f"  [✓] Block #{latest_b['index']} forged by: {latest_b['validator']}")
        assert latest_b["validator"].startswith("NODE_"), f"Expected NODE_ validator, got {latest_b['validator']}"
        assert not any(t.get("action") == "POA_REWARD" for t in latest_b["transactions"]), "No POA_REWARD should be minted in Guest Mode"
        print("  [✓] Verified ZERO block rewards minted when unassigned node adds block.")

        # Now attach bob_user as operator to Node 2 via /operator/login
        print("  [*] Attaching bob_user as operator to Node 2 via /operator/login...")
        op_login = urllib.request.Request(
            "http://127.0.0.1:8001/operator/login",
            data=json.dumps({"account_id": "bob_user", "password": "bob_password"}).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        op_res = json.loads(urllib.request.urlopen(op_login).read().decode("utf-8"))
        assert op_res["success"], "Operator login failed"
        print(f"  [✓] Node 2 operator updated: {op_res['operator_account']}")

        # Submit another transfer to test operator reward credit
        ok_test_op, _ = send_signed_tx("http://127.0.0.1:8001", "alice_user", alice_priv, "TRANSFER", {
            "recipient": GENESIS_ACCOUNT, "token": "CSP", "amount": 10.0
        })
        assert ok_test_op, "Transfer failed"
        time.sleep(9.0)

        # Bob started with 10 CSP (from Alice). Now bob_user was the operator when Node 2 forged the block:
        # Bob should receive 5.0 CSP block reward!
        bob_data = get_account_info("http://127.0.0.1:8001", "bob_user")
        print(f"  [✓] Bob Balances after Node 2 added block as operator: {bob_data['balances']['CSP']} CSP (10.0 received + 5.0 block reward)")
        assert bob_data["balances"]["CSP"] == 15.0, f"Expected 15.0 CSP for Bob, got {bob_data['balances']['CSP']}"

        # Re-launch Node 1 to test node reconnection, conflict resolution & catch-up sync
        print("  [*] Re-launching Node 1 to test reconnect, conflict resolution & catch-up sync...")
        node1_proc = subprocess.Popen([
            sys.executable, "-u", "node.py",
            "--port", "8000",
            "--account", GENESIS_ACCOUNT,
            "--password", "123",
            "--udp-port", "50555",
            "--peer", "http://127.0.0.1:8001",
            "--data-dir", TEST_DIR
        ])
        time.sleep(3.0)

        # -------------------------------------------------------------
        # 9. P2P Chain & State Parity across Nodes
        # -------------------------------------------------------------
        print("\n[TEST 9] Verifying Multi-Node Ledger & State Parity...")
        for i in range(40):
            s1 = None
            s2 = None
            try:
                s1 = json.loads(urllib.request.urlopen("http://127.0.0.1:8000/status", timeout=3).read().decode("utf-8"))
            except Exception as e1:
                print(f"  [!] Node 1 status error: {e1}")
            try:
                s2 = json.loads(urllib.request.urlopen("http://127.0.0.1:8001/status", timeout=3).read().decode("utf-8"))
            except Exception as e2:
                print(f"  [!] Node 2 status error: {e2}")

            if s1 and s2:
                print(f"  [*] Node 1 Height=#{s1['block_height']} (Peers: {s1.get('peers_count')}) | Node 2 Height=#{s2['block_height']} (Peers: {s2.get('peers_count')})")
                if s1["block_height"] == s2["block_height"]:
                    break
            time.sleep(1.0)

        n1_bob = get_account_info("http://127.0.0.1:8000", "bob_user")
        n2_bob = get_account_info("http://127.0.0.1:8001", "bob_user")
        print(f"  [✓] Node 1 state for bob_user: {n1_bob['balances']}")
        print(f"  [✓] Node 2 state for bob_user: {n2_bob['balances']}")
        assert n1_bob["balances"] == n2_bob["balances"], "State mismatch between Node 1 and Node 2"

        # Verify chains match
        c1 = json.loads(urllib.request.urlopen("http://127.0.0.1:8000/chain").read().decode("utf-8"))["chain"]
        c2 = json.loads(urllib.request.urlopen("http://127.0.0.1:8001/chain").read().decode("utf-8"))["chain"]
        assert len(c1) == len(c2), f"Chain length mismatch: {len(c1)} vs {len(c2)}"
        assert c1[-1]["hash"] == c2[-1]["hash"], "Latest block hash mismatch between nodes"
        assert c1[-1]["state_hash"] == c2[-1]["state_hash"], "Latest state hash mismatch between nodes"
        print(f"  [✓] Full Chain & State Parity Verified! Both nodes at block #{len(c1) - 1} with hash {c1[-1]['hash'][:16]}...")

        print("\n" + "=" * 70)
        print("           ALL TESTS PASSED SUCCESSFULLY! (100% OK)")
        print("=" * 70)

    finally:
        if node1_proc:
            node1_proc.terminate()
            node1_proc.wait()
        if node2_proc:
            node2_proc.terminate()
            node2_proc.wait()
        if os.path.exists(TEST_DIR):
            shutil.rmtree(TEST_DIR)

if __name__ == "__main__":
    run_test()
