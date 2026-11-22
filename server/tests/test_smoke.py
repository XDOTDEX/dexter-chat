"""End-to-end smoke tests against a real server subprocess.

Every test drives the server through the reference client, i.e. through
the same REST/WS + NaCl wire format the Flutter app speaks.
"""
import sqlite3
import time
import uuid

import httpx
import pytest

from refclient import RefClient, b64


def uniq(prefix: str) -> str:
    return f"{prefix}{uuid.uuid4().hex[:6]}"


def make_user(server_env, make_invite, prefix="user") -> RefClient:
    client = RefClient(server_env["base"])
    client.signup_wallet(make_invite(), uniq(prefix))
    return client


# ----------------------------------------------------------------------
# signup / auth
# ----------------------------------------------------------------------
def test_signup_requires_valid_invite(server_env):
    client = RefClient(server_env["base"])
    sig = client._wallet_sign_challenge()
    r = client.http.post("/auth/wallet/verify", json={
        "address": client.wallet.address, "signature": sig})
    assert r.status_code == 404          # not registered, no invite given
    sig = client._wallet_sign_challenge()
    r = client.http.post("/auth/wallet/verify", json={
        "address": client.wallet.address, "signature": sig,
        "invite_code": "DX-NOPE1234", "cashtag": uniq("x"),
        "enc_pubkey": client.pk_b64})
    assert r.status_code == 403          # bogus invite rejected


def test_wallet_signup_and_relogin(server_env, make_invite):
    client = make_user(server_env, make_invite, "walt")
    me = client.me()
    assert me["cashtag"] == client.user["cashtag"]
    assert me["has_wallet"] is True and me["has_phone"] is False
    assert me["cashtag_changed_at"] is None
    again = RefClient(server_env["base"])
    again.wallet = client.wallet         # same wallet, fresh session
    again.sk = client.sk
    again.pk_b64 = client.pk_b64
    data = again.login_wallet()
    assert data["user"]["cashtag"] == client.user["cashtag"]


def test_phone_signup_with_otp_stub(server_env, make_invite):
    client = RefClient(server_env["base"])
    phone = "+88017" + f"{uuid.uuid4().int % 100_000_000:08d}"
    client.signup_phone(make_invite(), phone, uniq("phn"))
    me = client.me()
    assert me["has_phone"] is True and me["has_wallet"] is False


def test_lookup_never_exposes_wallet_or_phone(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    r = alice.lookup("$" + bob.user["cashtag"])
    assert r.status_code == 200
    profile = r.json()
    assert profile["display"] == "$" + bob.user["cashtag"]
    assert "wallet_address" not in profile and "phone" not in profile
    assert alice.lookup("no_such_user_zzz").status_code == 404


# ----------------------------------------------------------------------
# E2E messaging
# ----------------------------------------------------------------------
def test_e2e_message_and_db_holds_only_ciphertext(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    marker = "SECRET-MARKER-" + uuid.uuid4().hex

    bob.ws_connect()
    try:
        alice.send_text(bob, marker, via_ws=False)
        frame = bob.wait_for(lambda f: f.get("type") == "message",
                             timeout=10)
        msg = frame["message"]
        assert msg["sender_cashtag"] == alice.user["cashtag"]
        payload = bob.decrypt_message(alice.pk_b64, msg)
        assert payload["kind"] == "text" and payload["text"] == marker
        bob.ws.send(__import__("json").dumps(
            {"type": "ack", "message_id": msg["id"]}))
    finally:
        bob.ws_close()

    # The server database — file bytes and every stored row — must not
    # contain the plaintext anywhere.
    with open(server_env["db_path"], "rb") as fh:
        assert marker.encode() not in fh.read()
    conn = sqlite3.connect(server_env["db_path"])
    rows = conn.execute("SELECT ciphertext FROM messages").fetchall()
    conn.close()
    for (ct,) in rows:
        assert marker.encode() not in bytes(ct)


def test_offline_queue_and_ack(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    text = "queued-" + uuid.uuid4().hex
    alice.send_text(bob, text)                       # bob offline
    queued = bob.pending()
    assert len(queued) == 1
    payload = bob.decrypt_message(alice.pk_b64, queued[0])
    assert payload["text"] == text
    assert bob.ack(queued[0]["id"]).json()["acked"] is True
    assert bob.pending() == []


def test_group_chat_with_shared_key(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    carol = make_user(server_env, make_invite, "carol")
    group = alice.create_group("Test Circle",
                               [bob.user["cashtag"], carol.user["cashtag"]])
    gid = group["id"]

    # Creator distributes the group secretbox key over the 1-to-1 channels.
    group_key = RefClient.new_secret_key()
    for member in (bob, carol):
        ct, nonce = alice.box_encrypt(member.pk_b64, __import__("json").dumps(
            {"kind": "group_key", "group_id": gid,
             "key": b64(group_key)}).encode())
        alice.send_rest({"to_cashtag": member.user["cashtag"],
                         "ciphertext": ct, "nonce": nonce})

    for member in (bob, carol):
        rows = member.pending()
        assert len(rows) == 1
        dist = member.decrypt_message(alice.pk_b64, rows[0])
        assert dist["kind"] == "group_key" and dist["group_id"] == gid
        assert dist["key"] == b64(group_key)
        member.ack(rows[0]["id"])

    # Group message: secretbox under the group key, fanned out by server.
    text = "hello circle " + uuid.uuid4().hex
    ct, nonce = RefClient.secret_encrypt(
        group_key, __import__("json").dumps(
            {"kind": "text", "text": text}).encode())
    r = alice.send_rest({"group_id": gid, "ciphertext": ct, "nonce": nonce})
    r.raise_for_status()
    assert len(r.json()["messages"]) == 2            # bob + carol copies
    for member in (bob, carol):
        rows = member.pending()
        assert len(rows) == 1 and rows[0]["group_id"] == gid
        payload = __import__("json").loads(RefClient.secret_decrypt(
            group_key, rows[0]["ciphertext"], rows[0]["nonce"]).decode())
        assert payload["text"] == text


# ----------------------------------------------------------------------
# view-limited photos
# ----------------------------------------------------------------------
def test_photo_view_limit_two_then_gone(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    photo_bytes = b"\x89PNG-FAKE-" + uuid.uuid4().bytes * 4
    key = RefClient.new_secret_key()
    ct, nonce = RefClient.secret_encrypt(key, photo_bytes)
    r = alice.upload_blob({"kind": "photo", "ciphertext": ct, "nonce": nonce,
                           "recipients": [bob.user["cashtag"]],
                           "view_limit": 2})
    r.raise_for_status()
    blob_id = r.json()["blob_id"]

    # The owner peeking must not consume the recipient's views.
    assert alice.fetch_blob(blob_id).json()["views_used"] == 0

    for expected_left in (1, 0):
        r = bob.fetch_blob(blob_id)
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["views_left"] == expected_left
        assert RefClient.secret_decrypt(
            key, body["ciphertext"], body["nonce"]) == photo_bytes
    # Third open: the blob is gone.
    assert bob.fetch_blob(blob_id).status_code == 404
    assert alice.fetch_blob(blob_id).status_code == 404

    # A stranger has no access at all.
    carol = make_user(server_env, make_invite, "carol")
    r = alice.upload_blob({"kind": "voice", "ciphertext": ct, "nonce": nonce,
                           "recipients": [bob.user["cashtag"]]})
    voice_id = r.json()["blob_id"]
    assert carol.fetch_blob(voice_id).status_code == 403
    assert bob.fetch_blob(voice_id).status_code == 200  # voice: no limit


# ----------------------------------------------------------------------
# self-destruct
# ----------------------------------------------------------------------
def test_self_destruct_message_is_purged(server_env, make_invite):
    alice = make_user(server_env, make_invite, "alice")
    bob = make_user(server_env, make_invite, "bob")
    alice.send_text(bob, "burn after reading", ttl_seconds=2)
    assert len(bob.pending()) == 1
    deadline = time.time() + 8
    while time.time() < deadline and bob.pending():
        time.sleep(0.4)
    assert bob.pending() == []                        # queue purged
    conn = sqlite3.connect(server_env["db_path"])
    n = conn.execute("SELECT COUNT(*) FROM messages WHERE recipient_id = ?",
                     (bob.user["user_id"],)).fetchone()[0]
    conn.close()
    assert n == 0                                     # row physically gone


# ----------------------------------------------------------------------
# $name changes
# ----------------------------------------------------------------------
def test_cashtag_change_recorded_and_old_name_released(
        server_env, make_invite):
    bob = make_user(server_env, make_invite, "bob")
    old_name = bob.user["cashtag"]
    new_name = uniq("bobby")
    r = bob.change_cashtag(new_name)
    assert r.status_code == 200, r.text
    me = bob.me()
    assert me["cashtag"] == new_name
    assert me["cashtag_changed_at"] is not None       # "last changed" date

    history = bob.cashtag_history()
    assert history[0]["old"] is None                  # initial registration
    change = history[-1]
    assert change["old"] == "$" + old_name
    assert change["new"] == "$" + new_name
    assert change["changed_at"] == pytest.approx(time.time(), abs=120)

    # Old $name released: lookup fails, someone else can take it.
    alice = make_user(server_env, make_invite, "alice")
    assert alice.lookup(old_name).status_code == 404
    newcomer = RefClient(server_env["base"])
    newcomer.signup_wallet(make_invite(), old_name)
    assert newcomer.user["cashtag"] == old_name
