"""Reference client implementing the exact wire/crypto format of the
Flutter app, used by the smoke tests.

Crypto suite (both sides):
- identity: X25519 keypair (PyNaCl `PrivateKey`)
- 1-to-1 messages: NaCl box (X25519 + XSalsa20-Poly1305), nonce sent apart
- blobs + group messages: NaCl secretbox (XSalsa20-Poly1305), random key
  per blob / per group, keys travel inside box-encrypted 1-to-1 messages
"""
import base64
import json
import time

import httpx
from eth_account import Account
from eth_account.messages import encode_defunct
from nacl.public import Box, PrivateKey, PublicKey
from nacl.secret import SecretBox
from nacl.utils import random as nacl_random
from websockets.sync.client import connect as ws_connect


def b64(raw: bytes) -> str:
    return base64.b64encode(raw).decode()


def unb64(text: str) -> bytes:
    return base64.b64decode(text)


class RefClient:
    def __init__(self, base_url: str):
        self.base = base_url
        self.http = httpx.Client(base_url=base_url, timeout=20,
                                 trust_env=False)  # never proxy localhost
        self.sk = PrivateKey.generate()
        self.pk_b64 = b64(bytes(self.sk.public_key))
        self.wallet = Account.create()
        self.token: str | None = None
        self.user: dict | None = None
        self.ws = None
        self.inbox: list[dict] = []

    # ------------------------------------------------------------- auth
    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    def _wallet_sign_challenge(self) -> str:
        msg = self.http.post(
            "/auth/wallet/challenge",
            json={"address": self.wallet.address}).json()["message"]
        signed = self.wallet.sign_message(encode_defunct(text=msg))
        return signed.signature.hex()

    def signup_wallet(self, invite: str, cashtag: str) -> dict:
        sig = self._wallet_sign_challenge()
        r = self.http.post("/auth/wallet/verify", json={
            "address": self.wallet.address, "signature": sig,
            "invite_code": invite, "cashtag": cashtag,
            "enc_pubkey": self.pk_b64})
        r.raise_for_status()
        return self._accept_session(r.json())

    def login_wallet(self) -> dict:
        sig = self._wallet_sign_challenge()
        r = self.http.post("/auth/wallet/verify", json={
            "address": self.wallet.address, "signature": sig})
        r.raise_for_status()
        return self._accept_session(r.json())

    def signup_phone(self, invite: str, phone: str, cashtag: str) -> dict:
        r = self.http.post("/auth/phone/request", json={"phone": phone})
        r.raise_for_status()
        code = r.json()["dev_code"]  # dev-mode stub returns the code
        r = self.http.post("/auth/phone/verify", json={
            "phone": phone, "code": code, "invite_code": invite,
            "cashtag": cashtag, "enc_pubkey": self.pk_b64})
        r.raise_for_status()
        return self._accept_session(r.json())

    def _accept_session(self, data: dict) -> dict:
        self.token = data["token"]
        self.user = data["user"]
        return data

    # ------------------------------------------------------------- rest
    def me(self) -> dict:
        r = self.http.get("/me", headers=self._headers())
        r.raise_for_status()
        return r.json()

    def change_cashtag(self, new: str):
        return self.http.post("/me/cashtag", json={"new_cashtag": new},
                              headers=self._headers())

    def cashtag_history(self) -> list:
        r = self.http.get("/me/cashtag-history", headers=self._headers())
        r.raise_for_status()
        return r.json()["history"]

    def lookup(self, cashtag: str):
        return self.http.get("/users/lookup", params={"cashtag": cashtag},
                             headers=self._headers())

    def create_group(self, name: str, members: list[str]) -> dict:
        r = self.http.post("/groups", json={"name": name,
                                            "members": members},
                           headers=self._headers())
        r.raise_for_status()
        return r.json()

    def send_rest(self, payload: dict):
        return self.http.post("/messages", json=payload,
                              headers=self._headers())

    def pending(self) -> list:
        r = self.http.get("/messages/pending", headers=self._headers())
        r.raise_for_status()
        return r.json()["messages"]

    def ack(self, message_id: int):
        return self.http.post("/messages/ack",
                              json={"message_id": message_id},
                              headers=self._headers())

    def upload_blob(self, payload: dict):
        return self.http.post("/blobs", json=payload,
                              headers=self._headers())

    def fetch_blob(self, blob_id: str):
        return self.http.get(f"/blobs/{blob_id}", headers=self._headers())

    # ------------------------------------------------------------- crypto
    def box_encrypt(self, peer_pk_b64: str, payload: bytes):
        box = Box(self.sk, PublicKey(unb64(peer_pk_b64)))
        enc = box.encrypt(payload)
        return b64(enc.ciphertext), b64(enc.nonce)

    def box_decrypt(self, peer_pk_b64: str, ct_b64: str, nonce_b64: str):
        box = Box(self.sk, PublicKey(unb64(peer_pk_b64)))
        return box.decrypt(unb64(ct_b64), unb64(nonce_b64))

    @staticmethod
    def secret_encrypt(key: bytes, payload: bytes):
        enc = SecretBox(key).encrypt(payload)
        return b64(enc.ciphertext), b64(enc.nonce)

    @staticmethod
    def secret_decrypt(key: bytes, ct_b64: str, nonce_b64: str):
        return SecretBox(key).decrypt(unb64(ct_b64), unb64(nonce_b64))

    @staticmethod
    def new_secret_key() -> bytes:
        return nacl_random(SecretBox.KEY_SIZE)

    def send_text(self, peer: "RefClient", text: str, ttl_seconds=None,
                  via_ws=False, extra: dict | None = None) -> dict:
        """Encrypt + send a JSON chat payload to a peer; returns server rows."""
        payload = {"kind": "text", "text": text}
        if extra:
            payload.update(extra)
        ct, nonce = self.box_encrypt(peer.pk_b64,
                                     json.dumps(payload).encode())
        body = {"to_cashtag": peer.user["cashtag"], "ciphertext": ct,
                "nonce": nonce}
        if ttl_seconds:
            body["ttl_seconds"] = ttl_seconds
        if via_ws:
            return self.ws_send(body)
        r = self.send_rest(body)
        r.raise_for_status()
        return r.json()["messages"]

    def decrypt_message(self, sender_pk_b64: str, msg: dict) -> dict:
        raw = self.box_decrypt(sender_pk_b64, msg["ciphertext"],
                               msg["nonce"])
        return json.loads(raw.decode())

    # ------------------------------------------------------------- ws
    def ws_connect(self) -> dict:
        ws_url = self.base.replace("http://", "ws://") + "/ws"
        try:
            ctx = ws_connect(ws_url, proxy=None)
        except TypeError:
            ctx = ws_connect(ws_url)
        self._ws_ctx = ctx
        self.ws = ctx.__enter__() if hasattr(ctx, "__enter__") else ctx
        self.ws.send(json.dumps({"type": "auth", "token": self.token}))
        frame = self.wait_for(
            lambda f: f.get("type") in ("auth_ok", "error"), timeout=10)
        assert frame["type"] == "auth_ok", frame
        return frame

    def ws_close(self):
        ctx = getattr(self, "_ws_ctx", None)
        if ctx is not None:
            try:
                ctx.__exit__(None, None, None)
            except Exception:
                pass
            self._ws_ctx = None
            self.ws = None
        elif self.ws is not None:
            try:
                self.ws.close()
            finally:
                self.ws = None

    def wait_for(self, pred, timeout: float = 10) -> dict:
        deadline = time.time() + timeout
        while True:
            for i, frame in enumerate(self.inbox):
                if pred(frame):
                    return self.inbox.pop(i)
            remaining = deadline - time.time()
            if remaining <= 0:
                raise TimeoutError(f"no matching frame; inbox={self.inbox}")
            try:
                raw = self.ws.recv(timeout=remaining)
            except TimeoutError:
                raise TimeoutError(
                    f"no matching frame; inbox={self.inbox}") from None
            self.inbox.append(json.loads(raw))

    def ws_send(self, body: dict) -> dict:
        ref = f"c{time.time_ns()}"
        frame = {"type": "send", "client_ref": ref, **body}
        self.ws.send(json.dumps(frame))
        return self.wait_for(
            lambda f: f.get("type") == "sent"
            and f.get("client_ref") == ref, timeout=10)
