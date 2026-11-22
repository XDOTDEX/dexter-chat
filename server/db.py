"""SQLite storage layer.

One shared connection guarded by a lock — more than enough for a private
circle of ~50-100 users, and it keeps the code simple and race-free.

IMPORTANT: the `messages` and `blobs` tables hold ONLY ciphertext produced
on the clients (NaCl box / secretbox). There is no plaintext column
anywhere in this schema, by design.
"""
import re
import sqlite3
import threading
import time

CASHTAG_RE = re.compile(r"^[a-z0-9_]{3,20}$")

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cashtag TEXT UNIQUE NOT NULL,              -- lowercase, without the $
    phone TEXT UNIQUE,                         -- E.164-ish, never exposed via API
    wallet_address TEXT UNIQUE,                -- lowercase 0x..., never exposed via API
    enc_pubkey TEXT NOT NULL,                  -- X25519 public key, base64
    created_at REAL NOT NULL,
    cashtag_changed_at REAL                    -- NULL until first change
);
CREATE TABLE IF NOT EXISTS cashtag_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id),
    old_cashtag TEXT,                          -- NULL for the initial registration
    new_cashtag TEXT NOT NULL,
    changed_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS invites (
    code TEXT PRIMARY KEY,
    created_at REAL NOT NULL,
    used_by INTEGER REFERENCES users(id),
    used_at REAL
);
CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    created_at REAL NOT NULL,
    expires_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS otp_codes (
    phone TEXT PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at REAL NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS wallet_challenges (
    address TEXT PRIMARY KEY,
    message TEXT NOT NULL,
    expires_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS contacts (
    owner_id INTEGER NOT NULL REFERENCES users(id),
    contact_id INTEGER NOT NULL REFERENCES users(id),
    added_at REAL NOT NULL,
    PRIMARY KEY (owner_id, contact_id)
);
CREATE TABLE IF NOT EXISTS groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    creator_id INTEGER NOT NULL REFERENCES users(id),
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS group_members (
    group_id INTEGER NOT NULL REFERENCES groups(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    PRIMARY KEY (group_id, user_id)
);
-- Offline queue + relay. ciphertext/nonce are NaCl box output from the
-- sender's client. expires_at implements the self-destruct timer.
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender_id INTEGER NOT NULL REFERENCES users(id),
    recipient_id INTEGER NOT NULL REFERENCES users(id),
    group_id INTEGER REFERENCES groups(id),
    ciphertext BLOB NOT NULL,
    nonce BLOB NOT NULL,
    created_at REAL NOT NULL,
    expires_at REAL,
    delivered_at REAL
);
-- Encrypted blobs: voice notes + view-limited photos (secretbox output).
CREATE TABLE IF NOT EXISTS blobs (
    id TEXT PRIMARY KEY,
    owner_id INTEGER NOT NULL REFERENCES users(id),
    kind TEXT NOT NULL CHECK (kind IN ('photo', 'voice')),
    ciphertext BLOB NOT NULL,
    nonce BLOB NOT NULL,
    view_limit INTEGER,                        -- photos: max opens; NULL = unlimited
    views_used INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    expires_at REAL
);
CREATE TABLE IF NOT EXISTS blob_access (
    blob_id TEXT NOT NULL REFERENCES blobs(id),
    user_id INTEGER NOT NULL REFERENCES users(id),
    PRIMARY KEY (blob_id, user_id)
);
"""


class DB:
    def __init__(self, path: str) -> None:
        import os
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.conn.executescript(SCHEMA)
            self.conn.commit()

    # -- generic helpers -------------------------------------------------
    def execute(self, sql: str, params=()) -> sqlite3.Cursor:
        with self.lock:
            cur = self.conn.execute(sql, params)
            self.conn.commit()
            return cur

    def query_one(self, sql: str, params=()):
        with self.lock:
            return self.conn.execute(sql, params).fetchone()

    def query_all(self, sql: str, params=()):
        with self.lock:
            return self.conn.execute(sql, params).fetchall()

    # -- users ------------------------------------------------------------
    def create_user(self, cashtag: str, enc_pubkey: str,
                    phone: str | None = None,
                    wallet_address: str | None = None) -> int:
        now = time.time()
        cur = self.execute(
            "INSERT INTO users (cashtag, phone, wallet_address, enc_pubkey,"
            " created_at) VALUES (?, ?, ?, ?, ?)",
            (cashtag, phone, wallet_address, enc_pubkey, now))
        user_id = cur.lastrowid
        self.execute(
            "INSERT INTO cashtag_history (user_id, old_cashtag, new_cashtag,"
            " changed_at) VALUES (?, NULL, ?, ?)", (user_id, cashtag, now))
        return user_id

    def user_by_id(self, user_id: int):
        return self.query_one("SELECT * FROM users WHERE id = ?", (user_id,))

    def user_by_cashtag(self, cashtag: str):
        return self.query_one("SELECT * FROM users WHERE cashtag = ?",
                              (cashtag.lower(),))

    def user_by_phone(self, phone: str):
        return self.query_one("SELECT * FROM users WHERE phone = ?", (phone,))

    def user_by_wallet(self, address: str):
        return self.query_one("SELECT * FROM users WHERE wallet_address = ?",
                              (address.lower(),))

    def change_cashtag(self, user_id: int, new_cashtag: str) -> None:
        """Rename a user: records history and releases the old $name."""
        now = time.time()
        row = self.user_by_id(user_id)
        old = row["cashtag"]
        self.execute("UPDATE users SET cashtag = ?, cashtag_changed_at = ?"
                     " WHERE id = ?", (new_cashtag, now, user_id))
        self.execute(
            "INSERT INTO cashtag_history (user_id, old_cashtag, new_cashtag,"
            " changed_at) VALUES (?, ?, ?, ?)",
            (user_id, old, new_cashtag, now))

    def cashtag_history(self, user_id: int):
        return self.query_all(
            "SELECT old_cashtag, new_cashtag, changed_at FROM cashtag_history"
            " WHERE user_id = ? ORDER BY changed_at ASC", (user_id,))


def valid_cashtag(name: str) -> bool:
    return bool(CASHTAG_RE.match(name or ""))


def public_profile(row, online: bool | None = None,
                    last_seen: float | None = None) -> dict:
    """What the API is allowed to show about a user.

    NEVER includes phone number or wallet address — the $name is the only
    address anyone needs.
    """
    out = {
        "user_id": row["id"],
        "cashtag": row["cashtag"],
        "display": "$" + row["cashtag"],
        "enc_pubkey": row["enc_pubkey"],
        "created_at": row["created_at"],
        "cashtag_changed_at": row["cashtag_changed_at"],
    }
    if online is not None:
        out["online"] = online
        out["last_seen"] = last_seen
    return out
