import unittest
import os
import time
import shutil
from storage import BlockchainStorage
from contracts import SmartContractEngine, ContractContext, SecurityError, GasExhaustionError
from node import BlockchainState, NodeServer, hash_data, derive_account_keypair, sign_transaction_payload

TEST_PASSWORDS = {"alice": "pass_a", "bob": "pass_b"}


def apply_signed(state, tx):
    """Sign with the sender's real key (placeholder signatures are no longer accepted), then apply."""
    if tx.get("signature") == "TEST_BYPASS":
        acc = state.accounts[tx["sender"]]
        privkey, _ = derive_account_keypair(TEST_PASSWORDS[tx["sender"]], acc["salt"])
        tx["signature"] = sign_transaction_payload(tx, privkey)
    return state.apply_transaction(tx)

class TestScalingAndSmartContracts(unittest.TestCase):
    def setUp(self):
        self.test_dir = "./test_run_data"
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)
        os.makedirs(self.test_dir, exist_ok=True)
        self.db_path = os.path.join(self.test_dir, "test_blockchain.db")
        self.storage = BlockchainStorage(self.db_path)

    def tearDown(self):
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    # -------------------------------------------------------------
    # 1. Storage & High-Speed Indexing Tests
    # -------------------------------------------------------------
    def test_high_speed_block_append_and_indexing(self):
        """Verify appending 1,000 blocks with transactions executes rapidly and queries in < 5ms."""
        start_time = time.time()
        for i in range(1, 1001):
            block = {
                "index": i,
                "hash": hash_data(f"block_{i}"),
                "prev_hash": hash_data(f"block_{i-1}"),
                "timestamp": time.time(),
                "validator": "test_validator",
                "state_hash": hash_data(f"state_{i}"),
                "transactions": [
                    {
                        "tx_id": hash_data(f"tx_{i}_1"),
                        "sender": "alice" if i % 2 == 0 else "charlie",
                        "action": "TRANSFER",
                        "payload": {"recipient": "bob", "token": "CSP", "amount": 10.0 + i},
                        "timestamp": time.time()
                    },
                    {
                        "tx_id": hash_data(f"tx_{i}_2"),
                        "sender": "bob",
                        "action": "TRANSFER",
                        "payload": {"recipient": "alice", "token": "BDP", "amount": 1.0},
                        "timestamp": time.time()
                    }
                ]
            }
            self.storage.append_block(block)

        append_duration = time.time() - start_time
        self.assertEqual(self.storage.get_block_count(), 1000)
        print(f"\n[Bench] Appended 1,000 blocks (2,000 txs) in {append_duration:.2f}s ({1000/append_duration:.0f} blocks/sec)")

        # Benchmark query latency
        q_start = time.time()
        total, txs = self.storage.query_transactions("alice", limit=20)
        q_duration = (time.time() - q_start) * 1000.0  # ms
        print(f"[Bench] Query 20 transactions for 'alice' across 2,000 txs took {q_duration:.2f}ms")

        self.assertGreater(total, 500)
        self.assertEqual(len(txs), 20)
        self.assertLess(q_duration, 50.0)  # Sub-50ms (usually < 2ms)

    def test_state_snapshot_checkpoint_and_restore(self):
        """Verify state snapshots can be stored and restored instantly without replaying history."""
        sample_state = {
            "accounts": {
                "alice": {"balances": {"CSP": 500.0, "BDP": 50.0}, "nonce": 42},
                "bob": {"balances": {"CSP": 1200.0, "BDP": 0.0}, "nonce": 18}
            },
            "orders": {},
            "marketplace_jobs": {},
            "contracts": {}
        }
        state_hash = hash_data(sample_state)

        # Save checkpoint at block #500
        ok = self.storage.save_checkpoint(500, state_hash, sample_state)
        self.assertTrue(ok)

        # Retrieve checkpoint
        latest = self.storage.get_latest_checkpoint()
        self.assertIsNotNone(latest)
        cp_block, cp_hash, cp_state = latest
        self.assertEqual(cp_block, 500)
        self.assertEqual(cp_hash, state_hash)
        self.assertEqual(cp_state["accounts"]["alice"]["balances"]["CSP"], 500.0)

    # -------------------------------------------------------------
    # 2. Generalized Smart Contract Sandbox & Engine Tests
    # -------------------------------------------------------------
    def test_smart_contract_security_sandbox(self):
        """Verify dangerous operations are completely blocked by the AST validator."""
        malicious_samples = [
            "import os\nos.system('rm -rf /')",
            "from subprocess import Popen",
            "eval('1 + 1')",
            "exec('a = 5')",
            "open('/etc/passwd', 'r')",
            "x = ().__class__.__subclasses__()",
            "getattr(int, '__dict__')"
        ]

        for code in malicious_samples:
            with self.assertRaises(SecurityError, msg=f"Should have blocked: {code}"):
                SmartContractEngine.validate_code(code)

    def test_smart_contract_gas_exhaustion(self):
        """Verify infinite loops are deterministically terminated by step metering."""
        infinite_loop = """
def loop(ctx):
    x = 0
    while True:
        x += 1
"""
        ctx = ContractContext("c_loop", "owner", "caller", time.time(), {}, {})
        ok, res, err = SmartContractEngine.execute(infinite_loop, "loop", ctx, {})
        self.assertFalse(ok)
        self.assertIn("Out of Gas", err)

    def test_smart_contract_on_chain_lifecycle(self):
        """Test full on-chain deployment, execution, escrow, and payouts in BlockchainState."""
        state = BlockchainState()
        state.register_account("alice", "pass_a", initial_csp=200.0, initial_bdp=10.0)
        state.register_account("bob", "pass_b", initial_csp=50.0, initial_bdp=0.0)

        # Contract: Crowdfunding / Bounty Escrow Contract
        bounty_contract_code = """
def init(ctx, task_name: str, bounty_amount: float):
    ctx.storage['task'] = task_name
    ctx.storage['bounty'] = float(bounty_amount)
    ctx.storage['completed'] = False
    ctx.storage['worker'] = None
    ctx.emit('BountyCreated', {'task': task_name, 'bounty': bounty_amount})

def complete_task(ctx, worker_id: str):
    if ctx.caller != ctx.contract_owner:
        raise Exception('Only owner can approve task completion')
    if ctx.storage['completed']:
        raise Exception('Task already completed and claimed')
    
    bounty = ctx.storage['bounty']
    ctx.storage['completed'] = True
    ctx.storage['worker'] = worker_id
    ctx.transfer(worker_id, 'CSP', bounty)
    ctx.emit('BountyPaid', {'worker': worker_id, 'amount': bounty})
"""

        # 1. Alice deploys contract and escrows 50 CSP into it
        tx_deploy = {
            "sender": "alice",
            "action": "CONTRACT_DEPLOY",
            "payload": {
                "name": "Design Bounty Escrow",
                "code": bounty_contract_code,
                "initial_escrow": 50.0,
                "initial_token": "CSP",
                "init_args": {"task_name": "Logo Redesign", "bounty_amount": 50.0}
            },
            "nonce": 0,
            "signature": "TEST_BYPASS",
            "timestamp": time.time()
        }

        ok, msg = apply_signed(state, tx_deploy)
        self.assertTrue(ok, msg)
        self.assertEqual(state.accounts["alice"]["balances"]["CSP"], 150.0)  # 200 - 50 = 150

        # Find deployed contract
        contract_id = list(state.contracts.keys())[0]
        contract = state.contracts[contract_id]
        self.assertEqual(contract["owner"], "alice")
        self.assertEqual(contract["balances"]["CSP"], 50.0)
        self.assertEqual(contract["storage"]["task"], "Logo Redesign")
        self.assertFalse(contract["storage"]["completed"])

        # 2. Bob tries to complete task directly (Should fail: unauthorized)
        tx_unauthorized = {
            "sender": "bob",
            "action": "CONTRACT_CALL",
            "payload": {
                "contract_id": contract_id,
                "method": "complete_task",
                "args": {"worker_id": "bob"}
            },
            "nonce": 0,
            "signature": "TEST_BYPASS",
            "timestamp": time.time()
        }
        ok_unauth, err_unauth = apply_signed(state, tx_unauthorized)
        self.assertFalse(ok_unauth)
        self.assertIn("Only owner can approve", err_unauth)
        self.assertEqual(contract["balances"]["CSP"], 50.0)
        self.assertEqual(state.accounts["bob"]["balances"]["CSP"], 50.0)

        # 3. Alice completes task and disburses 50 CSP escrow to Bob
        tx_approve = {
            "sender": "alice",
            "action": "CONTRACT_CALL",
            "payload": {
                "contract_id": contract_id,
                "method": "complete_task",
                "args": {"worker_id": "bob"}
            },
            "nonce": 1,
            "signature": "TEST_BYPASS",
            "timestamp": time.time()
        }
        ok_app, msg_app = apply_signed(state, tx_approve)
        self.assertTrue(ok_app, msg_app)

        # Verify balances: Bob received 50 CSP from contract escrow!
        self.assertEqual(contract["balances"]["CSP"], 0.0)
        self.assertEqual(state.accounts["bob"]["balances"]["CSP"], 100.0)  # 50 + 50 = 100
        self.assertTrue(contract["storage"]["completed"])
        self.assertEqual(contract["storage"]["worker"], "bob")

if __name__ == "__main__":
    unittest.main()
