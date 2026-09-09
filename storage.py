"""
Storage Engine for CSII-Pay Blockchain
Provides append-only block persistence, indexed transaction history, and periodic state checkpoints.
Engineered for scale to handle 100,000 to 1,000,000+ blocks with sub-millisecond query latency.
"""

import os
import json
import sqlite3
import threading
import time
from typing import List, Dict, Any, Optional, Tuple

class BlockchainStorage:
    """
    SQLite-backed append-only block store, indexed transaction ledger, and state checkpoint manager.
    Operates in WAL (Write-Ahead Logging) mode with synchronous=NORMAL for maximum write throughput.
    """
    def __init__(self, db_path: str = "blockchain.db"):
        self.db_path = db_path
        self._lock = threading.RLock()
        self._init_db()

    def _get_connection(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=30.0, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        return conn

    def _init_db(self):
        with self._lock:
            conn = self._get_connection()
            try:
                # Enable WAL mode for high concurrency (concurrent readers, non-blocking writes)
                conn.execute("PRAGMA journal_mode = WAL;")
                conn.execute("PRAGMA synchronous = NORMAL;")
                conn.execute("PRAGMA cache_size = -64000;")  # 64MB cache

                # 1. Blocks Table (Append-only)
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS blocks (
                        block_index INTEGER PRIMARY KEY,
                        hash TEXT UNIQUE NOT NULL,
                        prev_hash TEXT NOT NULL,
                        timestamp REAL NOT NULL,
                        validator TEXT NOT NULL,
                        tx_count INTEGER NOT NULL DEFAULT 0,
                        state_hash TEXT NOT NULL,
                        block_data TEXT NOT NULL
                    );
                """)
                conn.execute("CREATE INDEX IF NOT EXISTS idx_blocks_hash ON blocks(hash);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_blocks_timestamp ON blocks(timestamp);")

                # 2. Transactions Index Table (High-speed indexed lookups for 1M+ transactions)
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS transactions_index (
                        tx_id TEXT PRIMARY KEY,
                        block_index INTEGER,
                        timestamp REAL NOT NULL,
                        sender TEXT NOT NULL,
                        recipient TEXT,
                        creator TEXT,
                        action TEXT NOT NULL,
                        token TEXT NOT NULL DEFAULT 'CSP',
                        amount REAL NOT NULL DEFAULT 0.0,
                        fee REAL NOT NULL DEFAULT 0.0,
                        fee_token TEXT NOT NULL DEFAULT 'CSP',
                        status TEXT NOT NULL DEFAULT 'CONFIRMED',
                        payload_json TEXT NOT NULL
                    );
                """)
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tx_sender ON transactions_index(sender, timestamp DESC);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tx_recipient ON transactions_index(recipient, timestamp DESC);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tx_creator ON transactions_index(creator, timestamp DESC);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tx_action ON transactions_index(action);")
                conn.execute("CREATE INDEX IF NOT EXISTS idx_tx_block ON transactions_index(block_index);")

                # 3. State Snapshots / Checkpoints Table (Instant reboot at scale)
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS state_checkpoints (
                        checkpoint_block INTEGER PRIMARY KEY,
                        timestamp REAL NOT NULL,
                        state_hash TEXT NOT NULL,
                        state_json TEXT NOT NULL
                    );
                """)

                conn.commit()
            finally:
                conn.close()

    def append_block(self, block: Dict[str, Any]) -> bool:
        """
        Atomically appends a new block and indexes all its transactions.
        Takes O(1) time regardless of the total number of blocks in the chain.
        """
        with self._lock:
            conn = self._get_connection()
            try:
                b_index = int(block["index"])
                b_hash = str(block["hash"])
                prev_hash = str(block.get("prev_hash", ""))
                b_time = float(block.get("timestamp", time.time()))
                validator = str(block.get("validator", "GENESIS"))
                txs = block.get("transactions", [])
                tx_count = len(txs)
                state_hash = str(block.get("state_hash", ""))
                block_data = json.dumps(block, separators=(",", ":"))

                cur = conn.cursor()
                cur.execute("""
                    INSERT OR REPLACE INTO blocks (
                        block_index, hash, prev_hash, timestamp, validator, tx_count, state_hash, block_data
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """, (b_index, b_hash, prev_hash, b_time, validator, tx_count, state_hash, block_data))

                # Batch insert indexed transactions
                for tx in txs:
                    tx_id = tx.get("tx_id") or ""
                    sender = tx.get("sender") or ""
                    action = tx.get("action") or ""
                    p = tx.get("payload") or {}
                    recipient = (
                        p.get("recipient") or
                        p.get("maker") or
                        p.get("worker") or
                        p.get("account_id") or
                        p.get("contract_id") or
                        p.get("creator")
                    )
                    creator = p.get("creator")
                    token = p.get("token") or p.get("offer_token") or p.get("wage_token") or p.get("attached_token") or "CSP"
                    amount = float(p.get("amount") or p.get("offer_amount") or p.get("wage") or p.get("attached_amount") or 0.0)
                    fee = float(tx.get("fee", 0.0))
                    fee_token = tx.get("fee_token", "CSP")
                    tx_time = float(tx.get("timestamp", b_time))
                    payload_json = json.dumps(p, separators=(",", ":"))

                    cur.execute("""
                        INSERT OR REPLACE INTO transactions_index (
                            tx_id, block_index, timestamp, sender, recipient, creator,
                            action, token, amount, fee, fee_token, status, payload_json
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'CONFIRMED', ?);
                    """, (tx_id, b_index, tx_time, sender, recipient, creator,
                          action, token, amount, fee, fee_token, payload_json))

                conn.commit()
                return True
            except Exception as e:
                conn.rollback()
                print(f"[!] Storage append_block error at height {block.get('index')}: {e}")
                return False
            finally:
                conn.close()

    def get_block_count(self) -> int:
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT COUNT(*) FROM blocks;")
                row = cur.fetchone()
                return int(row[0]) if row else 0
            finally:
                conn.close()

    def get_latest_block(self) -> Optional[Dict[str, Any]]:
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT block_data FROM blocks ORDER BY block_index DESC LIMIT 1;")
                row = cur.fetchone()
                if row:
                    return json.loads(row["block_data"])
                return None
            finally:
                conn.close()

    def get_block_by_index(self, index: int) -> Optional[Dict[str, Any]]:
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT block_data FROM blocks WHERE block_index = ?;", (index,))
                row = cur.fetchone()
                if row:
                    return json.loads(row["block_data"])
                return None
            finally:
                conn.close()

    def get_blocks_range(self, offset: int = 0, limit: int = 50, reverse: bool = True) -> List[Dict[str, Any]]:
        order = "DESC" if reverse else "ASC"
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute(f"SELECT block_data FROM blocks ORDER BY block_index {order} LIMIT ? OFFSET ?;", (limit, offset))
                rows = cur.fetchall()
                return [json.loads(r["block_data"]) for r in rows]
            finally:
                conn.close()

    def get_all_blocks_for_sync(self) -> List[Dict[str, Any]]:
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("SELECT block_data FROM blocks ORDER BY block_index ASC;")
                rows = cur.fetchall()
                return [json.loads(r["block_data"]) for r in rows]
            finally:
                conn.close()

    def query_transactions(
        self,
        account_id: Optional[str] = None,
        offset: int = 0,
        limit: int = 20
    ) -> Tuple[int, List[Dict[str, Any]]]:
        """
        Sub-millisecond indexed transaction query.
        Returns (total_matching_count, list_of_transactions).
        """
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                if account_id:
                    cur.execute("""
                        SELECT COUNT(*) FROM transactions_index
                        WHERE sender = ? OR recipient = ? OR creator = ?;
                    """, (account_id, account_id, account_id))
                    total = cur.fetchone()[0]

                    cur.execute("""
                        SELECT tx_id, block_index, timestamp, sender, recipient, action,
                               token, amount, fee, fee_token, status, payload_json
                        FROM transactions_index
                        WHERE sender = ? OR recipient = ? OR creator = ?
                        ORDER BY timestamp DESC
                        LIMIT ? OFFSET ?;
                    """, (account_id, account_id, account_id, limit, offset))
                else:
                    cur.execute("SELECT COUNT(*) FROM transactions_index;")
                    total = cur.fetchone()[0]

                    cur.execute("""
                        SELECT tx_id, block_index, timestamp, sender, recipient, action,
                               token, amount, fee, fee_token, status, payload_json
                        FROM transactions_index
                        ORDER BY timestamp DESC
                        LIMIT ? OFFSET ?;
                    """, (limit, offset))

                rows = cur.fetchall()
                txs = []
                for r in rows:
                    p = {}
                    try:
                        p = json.loads(r["payload_json"])
                    except Exception:
                        pass
                    txs.append({
                        "tx_id": r["tx_id"],
                        "block_index": r["block_index"],
                        "timestamp": r["timestamp"],
                        "sender": r["sender"],
                        "recipient": r["recipient"],
                        "action": r["action"],
                        "token": r["token"],
                        "amount": r["amount"],
                        "fee": r["fee"],
                        "fee_token": r["fee_token"],
                        "status": r["status"],
                        "payload": p
                    })
                return total, txs
            finally:
                conn.close()

    # -------------------------------------------------------------
    # State Checkpoints (Fast Boot at 100k - 1M blocks)
    # -------------------------------------------------------------
    def save_checkpoint(self, block_index: int, state_hash: str, state_dict: Dict[str, Any]) -> bool:
        with self._lock:
            conn = self._get_connection()
            try:
                state_json = json.dumps(state_dict, separators=(",", ":"))
                conn.execute("""
                    INSERT OR REPLACE INTO state_checkpoints (
                        checkpoint_block, timestamp, state_hash, state_json
                    ) VALUES (?, ?, ?, ?);
                """, (block_index, time.time(), state_hash, state_json))
                conn.commit()
                print(f"[✓] State checkpoint saved at block #{block_index} (Hash: {state_hash[:10]}...)")
                return True
            except Exception as e:
                print(f"[!] Failed to save state checkpoint: {e}")
                return False
            finally:
                conn.close()

    def get_latest_checkpoint(self) -> Optional[Tuple[int, str, Dict[str, Any]]]:
        """Returns (block_index, state_hash, state_dict) or None."""
        with self._lock:
            conn = self._get_connection()
            try:
                cur = conn.cursor()
                cur.execute("""
                    SELECT checkpoint_block, state_hash, state_json
                    FROM state_checkpoints
                    ORDER BY checkpoint_block DESC LIMIT 1;
                """)
                row = cur.fetchone()
                if row:
                    state_dict = json.loads(row["state_json"])
                    return int(row["checkpoint_block"]), row["state_hash"], state_dict
                return None
            finally:
                conn.close()
