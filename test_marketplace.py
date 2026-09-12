import unittest
import hashlib
import time
from node import BlockchainState, hash_data, derive_account_keypair, sign_transaction_payload

class TestMarketplaceAndHistory(unittest.TestCase):
    def setUp(self):
        self.state = BlockchainState()
        self.state.register_account("student_alice", "pass1", initial_csp=100.0, initial_bdp=100.0)
        self.state.register_account("student_bob", "pass2", initial_csp=50.0, initial_bdp=100.0)
        self._passwords = {"student_alice": "pass1", "student_bob": "pass2"}

    def _apply(self, tx):
        """Sign the transaction with the sender's real key, then apply it (no bypass exists any more)."""
        if tx.get("signature") == "TEST_BYPASS":
            acc = self.state.accounts[tx["sender"]]
            privkey, _ = derive_account_keypair(self._passwords[tx["sender"]], acc["salt"])
            tx["signature"] = sign_transaction_payload(tx, privkey)
        return self.state.apply_transaction(tx)

    def test_marketplace_creation_and_escrow(self):
        secret = "123456"
        secret_hash = hashlib.sha256(secret.encode("utf-8")).hexdigest()
        
        tx_create = {
            "sender": "student_alice",
            "action": "MARKETPLACE_CREATE",
            "payload": {
                "job_id": "JOB_001",
                "title": "Build Flutter UI",
                "type": "student application",
                "category": "programming",
                "description": "Build mobile frontend",
                "deadline": "2026-09-15",
                "difficulty": 4,
                "line_id": "alice_csii",
                "wage": 30.0,
                "wage_token": "CSP",
                "secret_hash": secret_hash
            },
            "nonce": 0,
            "signature": "TEST_BYPASS",
            "timestamp": time.time()
        }
        
        ok, msg = self._apply(tx_create)
        self.assertTrue(ok, msg)
        self.assertEqual(self.state.accounts["student_alice"]["balances"]["CSP"], 70.0)
        self.assertIn("JOB_001", self.state.marketplace_jobs)
        self.assertEqual(self.state.marketplace_jobs["JOB_001"]["status"], "OPEN")

    def test_marketplace_wrong_codes_and_penalty(self):
        secret = "654321"
        secret_hash = hashlib.sha256(secret.encode("utf-8")).hexdigest()
        
        tx_create = {
            "sender": "student_alice",
            "action": "MARKETPLACE_CREATE",
            "payload": {
                "job_id": "JOB_002",
                "title": "Graphic Design Poster",
                "type": "student application",
                "category": "design",
                "description": "Poster for campus festival",
                "deadline": "Tomorrow",
                "difficulty": 2,
                "line_id": "alice_design",
                "wage": 20.0,
                "wage_token": "CSP",
                "secret_hash": secret_hash
            },
            "nonce": 0,
            "signature": "TEST_BYPASS",
            "timestamp": time.time()
        }
        self._apply(tx_create)
        
        # Bob tries wrong codes
        # Attempt 1
        tx_wrong1 = {
            "sender": "student_bob",
            "action": "MARKETPLACE_CLAIM",
            "payload": {"job_id": "JOB_002", "secret_code": "000000"},
            "nonce": 0,
            "signature": "TEST_BYPASS"
        }
        ok1, msg1 = self._apply(tx_wrong1)
        self.assertFalse(ok1)
        self.assertIn("attempt 1/3", msg1)
        self.assertEqual(self.state.accounts["student_bob"]["balances"]["CSP"], 50.0)

        # Attempt 2
        tx_wrong2 = {
            "sender": "student_bob",
            "action": "MARKETPLACE_CLAIM",
            "payload": {"job_id": "JOB_002", "secret_code": "111111"},
            "nonce": 1,
            "signature": "TEST_BYPASS"
        }
        ok2, msg2 = self._apply(tx_wrong2)
        self.assertFalse(ok2)
        self.assertIn("attempt 2/3", msg2)
        self.assertEqual(self.state.accounts["student_bob"]["balances"]["CSP"], 50.0)

        # Attempt 3
        tx_wrong3 = {
            "sender": "student_bob",
            "action": "MARKETPLACE_CLAIM",
            "payload": {"job_id": "JOB_002", "secret_code": "222222"},
            "nonce": 2,
            "signature": "TEST_BYPASS"
        }
        ok3, msg3 = self._apply(tx_wrong3)
        self.assertFalse(ok3)
        self.assertIn("attempt 3/3", msg3)
        self.assertEqual(self.state.accounts["student_bob"]["balances"]["CSP"], 50.0)

        # Attempt 4: Exceeds 3 times! Should be fined 10 CSP!
        tx_wrong4 = {
            "sender": "student_bob",
            "action": "MARKETPLACE_CLAIM",
            "payload": {"job_id": "JOB_002", "secret_code": "333333"},
            "nonce": 3,
            "signature": "TEST_BYPASS"
        }
        ok4, msg4 = self._apply(tx_wrong4)
        self.assertFalse(ok4)
        self.assertIn("Fined 10 CSP", msg4)
        # Verify 10 CSP was deducted from Bob's balance: 50.0 - 10.0 = 40.0 CSP!
        self.assertEqual(self.state.accounts["student_bob"]["balances"]["CSP"], 40.0)

        # Bob enters correct code on attempt 5!
        tx_correct = {
            "sender": "student_bob",
            "action": "MARKETPLACE_CLAIM",
            "payload": {"job_id": "JOB_002", "secret_code": "654321"},
            "nonce": 4,
            "signature": "TEST_BYPASS"
        }
        ok_win, msg_win = self._apply(tx_correct)
        self.assertTrue(ok_win, msg_win)
        # 40.0 + 20.0 wage = 60.0 CSP!
        self.assertEqual(self.state.accounts["student_bob"]["balances"]["CSP"], 60.0)
        self.assertEqual(self.state.marketplace_jobs["JOB_002"]["status"], "COMPLETED")
        self.assertEqual(self.state.marketplace_jobs["JOB_002"]["worker"], "student_bob")

if __name__ == "__main__":
    unittest.main()
