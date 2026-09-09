#!/usr/bin/env python3
"""
Diagnostic script to capture Block 8 details during the test run.
Run this ALONGSIDE the test to capture chain state.
"""
import sys, json, time, urllib.request

def poll():
    for _ in range(120):
        try:
            chain = json.loads(urllib.request.urlopen("http://127.0.0.1:8001/chain", timeout=2).read().decode())
            c = chain.get("chain", [])
            if len(c) >= 9:
                print("=== NODE 2 CHAIN (10 blocks) ===")
                for b in c:
                    txs = b.get("transactions", [])
                    print(f"Block #{b['index']}: state_hash={b['state_hash'][:12]} txs={len(txs)} validator={b['validator'][:20]}")
                    for tx in txs:
                        p = tx.get("payload", {})
                        print(f"  tx={tx['action']} sender={tx['sender']} fee={tx.get('fee','?')}")
                
                # Save chain for Node 1 to validate
                with open("/tmp/node2_chain_diag.json", "w") as f:
                    json.dump(chain, f, indent=2)
                print("\nSaved to /tmp/node2_chain_diag.json")
                
                # Now simulate Node 1 validation
                sys.path.insert(0, '.')
                from node import BlockchainState, hash_data, hash_password, derive_account_keypair, GENESIS_ACCOUNT, GENESIS_SALT, GENESIS_PASSWORD, NodeServer
                
                print("\n=== SIMULATING NODE 1 VALIDATION ===")
                temp_state = BlockchainState()
                pwd_hash, _ = hash_password(GENESIS_PASSWORD, GENESIS_SALT)
                _, genesis_pubkey = derive_account_keypair(GENESIS_PASSWORD, GENESIS_SALT)
                temp_state.register_account(
                    GENESIS_ACCOUNT, salt=GENESIS_SALT, password_hash=pwd_hash,
                    public_key=genesis_pubkey, initial_csp=0.0, initial_bdp=0.0
                )
                
                test_chain = c
                for i in range(len(test_chain)):
                    block = test_chain[i]
                    for tx in block.get("transactions", []):
                        ok, msg = temp_state.apply_transaction(tx)
                        if not ok:
                            print(f"  [FAIL] Block #{i} tx {tx.get('action')}: {msg}")
                    
                    computed = temp_state.get_state_hash()
                    stored = block["state_hash"]
                    match = "✓" if computed == stored else "✗ MISMATCH!"
                    print(f"Block #{i}: stored={stored[:12]} computed={computed[:12]} {match}")
                    
                    if computed != stored:
                        with temp_state.lock:
                            for acc, data in sorted(temp_state.accounts.items()):
                                print(f"  {acc}: CSP={data['balances']['CSP']}, BDP={data['balances']['BDP']}, nonce={data['nonce']}")
                return
        except Exception as e:
            pass
        time.sleep(1)
    print("Timed out waiting for node 2 to have 9 blocks")

poll()
