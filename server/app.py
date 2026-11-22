"""DexterChat API — FastAPI application.

Content rule: every message/blob body that passes through here is NaCl
ciphertext produced on a client. The server stores and relays it without
any ability to decrypt (it never sees a private key or a blob key).
"""
import asyncio
import base64
import binascii
import logging
import re
import time
import uuid
from contextlib import asynccontextmanager

from eth_account import Account
from eth_account.messages import encode_defunct
from fastapi import (Depends, FastAPI, Header, HTTPException, Request,
                     WebSocket, WebSocketDisconnect)

from .config import settings
from .db import DB, public_profile, valid_cashtag
from .otp import get_provider
from .presence import presence
from .security import (new_invite_code, new_nonce, new_otp_code,
                       new_session_token, sha256_hex)

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("dexterchat")

db = DB(settings.db_path)
otp_provider = get_provider()

RESERVED_CASHTAGS = {"admin", "owner", "support", "system", "dexterchat"}
PHONE_RE = re.compile(r"^\+?[0-9]{7,15}$")
MAX_MESSAGE_BYTES = 64 * 1024
MAX_TTL_SECONDS = 7 * 24 * 3600


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def b64d(value: str, field: str) -> bytes:
    try:
        return base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError, TypeError):
        raise HTTPException(400, f"{field} must be base64")


def b64e(raw: bytes) -> str:
    return base64.b64encode(raw).decode()


def check_pubkey(value: str) -> str:
    raw = b64d(value, "enc_pubkey")
    if len(raw) != 32:
        raise HTTPException(400, "enc_pubkey must be a 32-byte X25519 key")
    return value


def current_user(request: Request):
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        raise HTTPException(401, "missing bearer token")
    row = db.query_one(
        "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id"
        " WHERE s.token_hash = ? AND s.expires_at > ?",
        (sha256_hex(auth[7:]), time.time()))
    if row is None:
        raise HTTPException(401, "invalid or expired session")
    return row


def issue_session(user_row) -> dict:
    token = new_session_token()
    now = time.time()
    db.execute("INSERT INTO sessions (token_hash, user_id, created_at,"
               " expires_at) VALUES (?, ?, ?, ?)",
               (sha256_hex(token), user_row["id"], now,
                now + settings.session_ttl))
    return {"token": token,
            "user": public_profile(user_row, presence.is_online(user_row["id"]),
                                   presence.last_seen_at(user_row["id"]))}


def check_invite(code: str):
    row = db.query_one("SELECT * FROM invites WHERE code = ?", (code or "",))
    if row is None or row["used_by"] is not None:
        raise HTTPException(403, "invalid or already-used invite code")
    return row


def register_user(cashtag: str, enc_pubkey: str, invite_code: str,
                  phone: str | None = None,
                  wallet_address: str | None = None):
    """Shared signup path for wallet + phone registration."""
    cashtag = (cashtag or "").lower().lstrip("$")
    if not valid_cashtag(cashtag) or cashtag in RESERVED_CASHTAGS:
        raise HTTPException(400, "invalid $name (3-20 chars: a-z, 0-9, _)")
    check_pubkey(enc_pubkey)
    invite = check_invite(invite_code)
    if db.user_by_cashtag(cashtag):
        raise HTTPException(409, "$name already taken")
    if phone and db.user_by_phone(phone):
        raise HTTPException(409, "phone already registered")
    if wallet_address and db.user_by_wallet(wallet_address):
        raise HTTPException(409, "wallet already registered")
    user_id = db.create_user(cashtag, enc_pubkey, phone=phone,
                             wallet_address=wallet_address)
    db.execute("UPDATE invites SET used_by = ?, used_at = ? WHERE code = ?",
               (user_id, time.time(), invite["code"]))
    return db.user_by_id(user_id)


def resolve_user_ref(ref) -> object:
    """Accept a user id (int), a cashtag ('dexter' or '$dexter')."""
    if isinstance(ref, int):
        row = db.user_by_id(ref)
    elif isinstance(ref, str):
        row = db.user_by_cashtag(ref.lstrip("$"))
    else:
        row = None
    if row is None:
        raise HTTPException(404, f"user not found: {ref}")
    return row


def message_dict(row) -> dict:
    sender = db.user_by_id(row["sender_id"])
    return {
        "id": row["id"],
        "sender_id": row["sender_id"],
        "sender_cashtag": sender["cashtag"] if sender else None,
        "recipient_id": row["recipient_id"],
        "group_id": row["group_id"],
        "ciphertext": b64e(bytes(row["ciphertext"])),
        "nonce": b64e(bytes(row["nonce"])),
        "created_at": row["created_at"],
        "expires_at": row["expires_at"],
    }


def purge_expired() -> list[dict]:
    """Delete self-destructed messages/blobs whose time has come.

    Returns the purged message rows so the caller can notify recipients.
    """
    now = time.time()
    expired = db.query_all(
        "SELECT * FROM messages WHERE expires_at IS NOT NULL"
        " AND expires_at <= ?", (now,))
    if expired:
        db.execute("DELETE FROM messages WHERE expires_at IS NOT NULL"
                   " AND expires_at <= ?", (now,))
    db.execute("DELETE FROM blob_access WHERE blob_id IN"
               " (SELECT id FROM blobs WHERE expires_at IS NOT NULL"
               " AND expires_at <= ?)", (now,))
    db.execute("DELETE FROM blobs WHERE expires_at IS NOT NULL"
               " AND expires_at <= ?", (now,))
    return [message_dict(r) for r in expired]


async def sweeper() -> None:
    while True:
        try:
            for msg in purge_expired():
                await presence.send_to(msg["recipient_id"], {
                    "type": "expired", "message_id": msg["id"],
                    "group_id": msg["group_id"]})
        except Exception:  # never let the sweeper die
            log.exception("sweeper error")
        await asyncio.sleep(settings.sweep_interval)


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(sweeper())
    log.info("DexterChat server up (dev_mode=%s, db=%s)",
             settings.dev_mode, settings.db_path)
    yield
    task.cancel()


app = FastAPI(title="DexterChat", version="0.1.0", lifespan=lifespan)


# --------------------------------------------------------------------------
# health + admin
# --------------------------------------------------------------------------
@app.get("/health")
def health():
    return {"ok": True, "dev_mode": settings.dev_mode}


@app.post("/admin/invites")
def create_invite(x_admin_key: str = Header(default="")):
    if x_admin_key != settings.admin_key:
        raise HTTPException(401, "bad admin key")
    code = new_invite_code()
    db.execute("INSERT INTO invites (code, created_at) VALUES (?, ?)",
               (code, time.time()))
    return {"invite_code": code}


# --------------------------------------------------------------------------
# wallet auth (EVM personal_sign over a server nonce)
# --------------------------------------------------------------------------
def wallet_challenge_message(address: str, nonce: str) -> str:
    return ("DexterChat wallet login\n"
            f"Address: {address}\n"
            f"Nonce: {nonce}\n"
            "Signing this message proves you own the wallet. "
            "It costs no gas.")


@app.post("/auth/wallet/challenge")
def wallet_challenge(body: dict):
    address = (body.get("address") or "").lower()
    if not re.fullmatch(r"0x[0-9a-f]{40}", address):
        raise HTTPException(400, "invalid EVM address")
    message = wallet_challenge_message(address, new_nonce())
    db.execute("INSERT OR REPLACE INTO wallet_challenges"
               " (address, message, expires_at) VALUES (?, ?, ?)",
               (address, message, time.time() + settings.challenge_ttl))
    return {"message": message}


def verify_wallet_signature(address: str, signature: str) -> None:
    row = db.query_one("SELECT * FROM wallet_challenges WHERE address = ?",
                       (address,))
    if row is None or row["expires_at"] <= time.time():
        raise HTTPException(401, "challenge missing or expired — "
                                 "request a new one")
    try:
        recovered = Account.recover_message(
            encode_defunct(text=row["message"]),
            signature=bytes.fromhex(signature.removeprefix("0x")))
    except Exception:
        raise HTTPException(401, "bad signature")
    if recovered.lower() != address:
        raise HTTPException(401, "signature does not match address")
    db.execute("DELETE FROM wallet_challenges WHERE address = ?", (address,))


@app.post("/auth/wallet/verify")
def wallet_verify(body: dict):
    address = (body.get("address") or "").lower()
    signature = body.get("signature") or ""
    verify_wallet_signature(address, signature)
    user = db.user_by_wallet(address)
    if user is None:
        # New wallet → this call doubles as signup when invite + $name +
        # encryption key are supplied.
        if not body.get("invite_code"):
            raise HTTPException(404, "wallet not registered; signup needs"
                                     " invite_code, cashtag, enc_pubkey")
        user = register_user(body.get("cashtag"), body.get("enc_pubkey"),
                             body["invite_code"], wallet_address=address)
    return issue_session(user)


# --------------------------------------------------------------------------
# phone OTP auth (provider stubbed — see otp.py)
# --------------------------------------------------------------------------
def clean_phone(raw: str) -> str:
    phone = (raw or "").replace(" ", "").replace("-", "")
    if not PHONE_RE.fullmatch(phone):
        raise HTTPException(400, "invalid phone number")
    return phone


@app.post("/auth/phone/request")
def phone_request(body: dict):
    phone = clean_phone(body.get("phone"))
    code = new_otp_code()
    db.execute("INSERT OR REPLACE INTO otp_codes (phone, code_hash,"
               " expires_at, attempts) VALUES (?, ?, ?, 0)",
               (phone, sha256_hex(code),
                time.time() + settings.otp_ttl))
    otp_provider.send(phone, code)
    out = {"sent": True, "ttl_seconds": settings.otp_ttl}
    if settings.dev_mode:
        out["dev_code"] = code  # DEV ONLY — never in production
    return out


@app.post("/auth/phone/verify")
def phone_verify(body: dict):
    phone = clean_phone(body.get("phone"))
    code = (body.get("code") or "").strip()
    row = db.query_one("SELECT * FROM otp_codes WHERE phone = ?", (phone,))
    if row is None or row["expires_at"] <= time.time():
        raise HTTPException(401, "code missing or expired")
    if row["attempts"] >= settings.otp_max_attempts:
        raise HTTPException(429, "too many attempts — request a new code")
    if sha256_hex(code) != row["code_hash"]:
        db.execute("UPDATE otp_codes SET attempts = attempts + 1"
                   " WHERE phone = ?", (phone,))
        raise HTTPException(401, "wrong code")
    db.execute("DELETE FROM otp_codes WHERE phone = ?", (phone,))
    user = db.user_by_phone(phone)
    if user is None:
        if not body.get("invite_code"):
            raise HTTPException(404, "phone not registered; signup needs"
                                     " invite_code, cashtag, enc_pubkey")
        user = register_user(body.get("cashtag"), body.get("enc_pubkey"),
                             body["invite_code"], phone=phone)
    return issue_session(user)


# --------------------------------------------------------------------------
# profile + $name registry
# --------------------------------------------------------------------------
@app.get("/me")
def me(user=Depends(current_user)):
    out = public_profile(user, presence.is_online(user["id"]),
                         presence.last_seen_at(user["id"]))
    out["has_wallet"] = user["wallet_address"] is not None
    out["has_phone"] = user["phone"] is not None
    return out


@app.post("/me/cashtag")
def change_cashtag(body: dict, user=Depends(current_user)):
    new = (body.get("new_cashtag") or "").lower().lstrip("$")
    if not valid_cashtag(new) or new in RESERVED_CASHTAGS:
        raise HTTPException(400, "invalid $name (3-20 chars: a-z, 0-9, _)")
    if new == user["cashtag"]:
        raise HTTPException(400, "that is already your $name")
    if db.user_by_cashtag(new):
        raise HTTPException(409, "$name already taken")
    db.change_cashtag(user["id"], new)   # old $name is released here
    return public_profile(db.user_by_id(user["id"]))


@app.get("/me/cashtag-history")
def my_cashtag_history(user=Depends(current_user)):
    return {"history": [
        {"old": ("$" + r["old_cashtag"]) if r["old_cashtag"] else None,
         "new": "$" + r["new_cashtag"],
         "changed_at": r["changed_at"]}
        for r in db.cashtag_history(user["id"])]}


@app.post("/me/wallet/challenge")
def my_wallet_challenge(body: dict, user=Depends(current_user)):
    return wallet_challenge(body)


@app.post("/me/wallet/link")
def my_wallet_link(body: dict, user=Depends(current_user)):
    address = (body.get("address") or "").lower()
    verify_wallet_signature(address, body.get("signature") or "")
    other = db.user_by_wallet(address)
    if other is not None and other["id"] != user["id"]:
        raise HTTPException(409, "wallet already linked to another account")
    db.execute("UPDATE users SET wallet_address = ? WHERE id = ?",
               (address, user["id"]))
    return {"linked": True}


@app.get("/users/lookup")
def lookup(cashtag: str, user=Depends(current_user)):
    row = db.user_by_cashtag(cashtag.lstrip("$"))
    if row is None:
        raise HTTPException(404, "no user with that $name")
    return public_profile(row, presence.is_online(row["id"]),
                          presence.last_seen_at(row["id"]))


# --------------------------------------------------------------------------
# contacts
# --------------------------------------------------------------------------
@app.get("/contacts")
def list_contacts(user=Depends(current_user)):
    rows = db.query_all(
        "SELECT u.* FROM contacts c JOIN users u ON u.id = c.contact_id"
        " WHERE c.owner_id = ? ORDER BY u.cashtag", (user["id"],))
    return {"contacts": [public_profile(
        r, presence.is_online(r["id"]), presence.last_seen_at(r["id"]))
        for r in rows]}


@app.post("/contacts")
def add_contact(body: dict, user=Depends(current_user)):
    target = resolve_user_ref(body.get("cashtag") or body.get("user_id"))
    if target["id"] == user["id"]:
        raise HTTPException(400, "cannot add yourself")
    db.execute("INSERT OR IGNORE INTO contacts (owner_id, contact_id,"
               " added_at) VALUES (?, ?, ?)",
               (user["id"], target["id"], time.time()))
    return {"added": target["cashtag"]}


@app.delete("/contacts/{cashtag}")
def remove_contact(cashtag: str, user=Depends(current_user)):
    target = db.user_by_cashtag(cashtag.lstrip("$"))
    if target:
        db.execute("DELETE FROM contacts WHERE owner_id = ?"
                   " AND contact_id = ?", (user["id"], target["id"]))
    return {"removed": True}


# --------------------------------------------------------------------------
# groups (key distribution is client-side, over the 1-to-1 channels)
# --------------------------------------------------------------------------
@app.post("/groups")
def create_group(body: dict, user=Depends(current_user)):
    name = (body.get("name") or "").strip()
    if not name or len(name) > 60:
        raise HTTPException(400, "group name required (max 60 chars)")
    member_ids = {user["id"]}
    for ref in body.get("members", []):
        member_ids.add(resolve_user_ref(ref)["id"])
    cur = db.execute("INSERT INTO groups (name, creator_id, created_at)"
                     " VALUES (?, ?, ?)", (name, user["id"], time.time()))
    group_id = cur.lastrowid
    for uid in member_ids:
        db.execute("INSERT INTO group_members (group_id, user_id)"
                   " VALUES (?, ?)", (group_id, uid))
    return group_detail(group_id, user)


def group_detail(group_id: int, user) -> dict:
    row = db.query_one("SELECT * FROM groups WHERE id = ?", (group_id,))
    if row is None:
        raise HTTPException(404, "group not found")
    members = db.query_all(
        "SELECT u.* FROM group_members gm JOIN users u ON u.id = gm.user_id"
        " WHERE gm.group_id = ?", (group_id,))
    if user["id"] not in [m["id"] for m in members]:
        raise HTTPException(403, "not a group member")
    return {"id": row["id"], "name": row["name"],
            "creator_id": row["creator_id"], "created_at": row["created_at"],
            "members": [public_profile(m) for m in members]}


@app.get("/groups")
def list_groups(user=Depends(current_user)):
    rows = db.query_all(
        "SELECT g.id FROM groups g JOIN group_members gm"
        " ON gm.group_id = g.id WHERE gm.user_id = ?", (user["id"],))
    return {"groups": [group_detail(r["id"], user) for r in rows]}


@app.get("/groups/{group_id}")
def get_group(group_id: int, user=Depends(current_user)):
    return group_detail(group_id, user)


# --------------------------------------------------------------------------
# messages: store-and-forward of ciphertext
# --------------------------------------------------------------------------
def store_message(sender, body: dict) -> list[dict]:
    """Shared by the WebSocket and REST send paths."""
    ciphertext = b64d(body.get("ciphertext") or "", "ciphertext")
    nonce = b64d(body.get("nonce") or "", "nonce")
    if not ciphertext or len(ciphertext) > MAX_MESSAGE_BYTES:
        raise HTTPException(400, "ciphertext missing or too large")
    if len(nonce) != 24:
        raise HTTPException(400, "nonce must be 24 bytes (NaCl box)")
    ttl = body.get("ttl_seconds")
    expires_at = None
    if ttl:
        ttl = int(ttl)
        if ttl <= 0 or ttl > MAX_TTL_SECONDS:
            raise HTTPException(400, "ttl_seconds out of range")
        expires_at = time.time() + ttl

    group_id = body.get("group_id")
    if group_id:
        detail = group_detail(int(group_id), sender)  # 403 if not member
        recipients = [m["user_id"] for m in detail["members"]
                      if m["user_id"] != sender["id"]]
    else:
        ref = body.get("to_user_id", body.get("to_cashtag"))
        if ref is None:
            raise HTTPException(400, "to_cashtag/to_user_id or group_id"
                                     " required")
        target = resolve_user_ref(ref)
        if target["id"] == sender["id"]:
            raise HTTPException(400, "cannot message yourself")
        recipients = [target["id"]]

    created = []
    now = time.time()
    for rid in recipients:
        cur = db.execute(
            "INSERT INTO messages (sender_id, recipient_id, group_id,"
            " ciphertext, nonce, created_at, expires_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (sender["id"], rid, group_id, ciphertext, nonce, now,
             expires_at))
        created.append(message_dict(db.query_one(
            "SELECT * FROM messages WHERE id = ?", (cur.lastrowid,))))
    return created


async def deliver(created: list[dict]) -> None:
    for msg in created:
        await presence.send_to(msg["recipient_id"],
                               {"type": "message", "message": msg})


@app.post("/messages")
async def send_message_rest(body: dict, user=Depends(current_user)):
    created = store_message(user, body)
    await deliver(created)
    return {"messages": created}


@app.get("/messages/pending")
def pending_messages(user=Depends(current_user)):
    purge_expired()
    rows = db.query_all(
        "SELECT * FROM messages WHERE recipient_id = ?"
        " ORDER BY created_at ASC", (user["id"],))
    return {"messages": [message_dict(r) for r in rows]}


@app.post("/messages/ack")
def ack_message(body: dict, user=Depends(current_user)):
    cur = db.execute("DELETE FROM messages WHERE id = ? AND recipient_id = ?",
                     (int(body.get("message_id") or 0), user["id"]))
    return {"acked": cur.rowcount > 0}


# --------------------------------------------------------------------------
# encrypted blobs: voice notes + view-limited photos
# --------------------------------------------------------------------------
@app.post("/blobs")
def upload_blob(body: dict, user=Depends(current_user)):
    kind = body.get("kind")
    if kind not in ("photo", "voice"):
        raise HTTPException(400, "kind must be 'photo' or 'voice'")
    ciphertext = b64d(body.get("ciphertext") or "", "ciphertext")
    nonce = b64d(body.get("nonce") or "", "nonce")
    if not ciphertext or len(ciphertext) > settings.max_blob_bytes:
        raise HTTPException(400, "ciphertext missing or too large")
    if len(nonce) != 24:
        raise HTTPException(400, "nonce must be 24 bytes (NaCl secretbox)")

    access_ids = {user["id"]}
    if body.get("group_id"):
        detail = group_detail(int(body["group_id"]), user)
        access_ids.update(m["user_id"] for m in detail["members"])
    for ref in body.get("recipients", []):
        access_ids.add(resolve_user_ref(ref)["id"])
    if len(access_ids) < 2:
        raise HTTPException(400, "at least one recipient required")

    view_limit = body.get("view_limit")
    if view_limit is not None:
        view_limit = int(view_limit)
        if view_limit < 1 or view_limit > 100:
            raise HTTPException(400, "view_limit must be 1..100")
        if kind != "photo":
            raise HTTPException(400, "view_limit applies to photos")
    ttl = body.get("ttl_seconds")
    expires_at = None
    if ttl:
        ttl = int(ttl)
        if ttl <= 0 or ttl > MAX_TTL_SECONDS:
            raise HTTPException(400, "ttl_seconds out of range")
        expires_at = time.time() + ttl

    blob_id = uuid.uuid4().hex
    db.execute("INSERT INTO blobs (id, owner_id, kind, ciphertext, nonce,"
               " view_limit, created_at, expires_at)"
               " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
               (blob_id, user["id"], kind, ciphertext, nonce, view_limit,
                time.time(), expires_at))
    for uid in access_ids:
        db.execute("INSERT INTO blob_access (blob_id, user_id)"
                   " VALUES (?, ?)", (blob_id, uid))
    return {"blob_id": blob_id, "view_limit": view_limit,
            "expires_at": expires_at}


@app.get("/blobs/{blob_id}")
def fetch_blob(blob_id: str, user=Depends(current_user)):
    row = db.query_one("SELECT * FROM blobs WHERE id = ?", (blob_id,))
    if row is None:
        raise HTTPException(404, "blob not found (already gone?)")
    allowed = db.query_one("SELECT 1 FROM blob_access WHERE blob_id = ?"
                           " AND user_id = ?", (blob_id, user["id"]))
    if allowed is None and row["owner_id"] != user["id"]:
        raise HTTPException(403, "no access to this blob")
    if row["expires_at"] is not None and row["expires_at"] <= time.time():
        _delete_blob(blob_id)
        raise HTTPException(410, "blob expired")

    views_used = row["views_used"]
    if row["view_limit"] is not None and row["owner_id"] != user["id"]:
        views_used += 1
        db.execute("UPDATE blobs SET views_used = ? WHERE id = ?",
                   (views_used, blob_id))
    out = {
        "blob_id": blob_id, "kind": row["kind"],
        "ciphertext": b64e(bytes(row["ciphertext"])),
        "nonce": b64e(bytes(row["nonce"])),
        "view_limit": row["view_limit"], "views_used": views_used,
        "views_left": (row["view_limit"] - views_used
                       if row["view_limit"] is not None else None),
        "expires_at": row["expires_at"],
    }
    if (row["view_limit"] is not None and row["owner_id"] != user["id"]
            and views_used >= row["view_limit"]):
        _delete_blob(blob_id)  # last allowed view — blob is gone now
    return out


def _delete_blob(blob_id: str) -> None:
    db.execute("DELETE FROM blob_access WHERE blob_id = ?", (blob_id,))
    db.execute("DELETE FROM blobs WHERE id = ?", (blob_id,))


# --------------------------------------------------------------------------
# WebSocket relay
# --------------------------------------------------------------------------
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    user = None
    try:
        first = await asyncio.wait_for(ws.receive_json(), timeout=15)
        token = first.get("token") or ws.query_params.get("token") or ""
        row = db.query_one(
            "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id"
            " WHERE s.token_hash = ? AND s.expires_at > ?",
            (sha256_hex(token), time.time()))
        if first.get("type") != "auth" or row is None:
            await ws.send_json({"type": "error", "error": "auth failed"})
            await ws.close(code=4401)
            return
        user = row
        came_online = presence.add(user["id"], ws)
        await ws.send_json({"type": "auth_ok",
                            "user": public_profile(user, True)})
        purge_expired()
        pending = db.query_all(
            "SELECT * FROM messages WHERE recipient_id = ?"
            " ORDER BY created_at ASC", (user["id"],))
        for msg in pending:
            await ws.send_json({"type": "message",
                                "message": message_dict(msg)})
        if came_online:
            await presence.broadcast({
                "type": "presence", "user_id": user["id"],
                "cashtag": user["cashtag"], "online": True,
                "last_seen": presence.last_seen_at(user["id"])})
        while True:
            frame = await ws.receive_json()
            ftype = frame.get("type")
            if ftype == "ping":
                await ws.send_json({"type": "pong"})
            elif ftype == "send":
                try:
                    created = store_message(user, frame)
                except HTTPException as exc:
                    await ws.send_json({"type": "error",
                                        "client_ref": frame.get("client_ref"),
                                        "error": exc.detail})
                    continue
                await deliver(created)
                await ws.send_json({
                    "type": "sent", "client_ref": frame.get("client_ref"),
                    "message_ids": [m["id"] for m in created]})
            elif ftype == "ack":
                db.execute("DELETE FROM messages WHERE id = ?"
                           " AND recipient_id = ?",
                           (int(frame.get("message_id") or 0), user["id"]))
            else:
                await ws.send_json({"type": "error",
                                    "error": f"unknown frame {ftype}"})
    except (WebSocketDisconnect, asyncio.TimeoutError):
        pass
    finally:
        if user is not None:
            went_offline = presence.remove(user["id"], ws)
            if went_offline:
                await presence.broadcast({
                    "type": "presence", "user_id": user["id"],
                    "cashtag": user["cashtag"], "online": False,
                    "last_seen": presence.last_seen_at(user["id"])})
