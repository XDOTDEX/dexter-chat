# DexterChat server (Phase 1)

Private, invite-only, end-to-end-encrypted messaging backend for a small
circle (~50–100 people). FastAPI + SQLite, one process, no external
services.

**The server can never read message content.** Clients encrypt with NaCl
(X25519 + XSalsa20-Poly1305 `box` for messages, `secretbox` for blobs).
The database stores only ciphertext, nonces, and routing metadata.

## Run it

```bash
cd messaging-app
python3 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
.venv/bin/python -m server            # http://127.0.0.1:8642
```

Create invite codes (owner only):

```bash
.venv/bin/python -m server.cli create-invite 5
# or over HTTP:  POST /admin/invites  with header  X-Admin-Key: <MSG_ADMIN_KEY>
```

## Configuration (environment)

| Var | Default | Meaning |
|---|---|---|
| `MSG_DB` | `server/data/app.db` | SQLite path |
| `MSG_HOST` / `MSG_PORT` | `127.0.0.1` / `8642` | bind |
| `MSG_ADMIN_KEY` | `dev-admin-key-change-me` | key for invite creation — CHANGE IT |
| `MSG_DEV_MODE` | `1` | dev only: OTP responses include `dev_code`. Set `0` in production |
| `MSG_SWEEP_INTERVAL` | `1.0` | seconds between self-destruct sweeps |

## Auth

- **Wallet (EVM):** `POST /auth/wallet/challenge {address}` → sign the
  returned message with `personal_sign` → `POST /auth/wallet/verify
  {address, signature}`. For a brand-new wallet, also send `invite_code`,
  `cashtag`, `enc_pubkey` in the verify call to sign up in one step.
- **Phone OTP (stub):** `POST /auth/phone/request {phone}` →
  `POST /auth/phone/verify {phone, code}` (+ invite fields on first use).
  Delivery sits behind `OtpProvider` (`server/otp.py`); Phase 1 ships a
  dev provider that logs the code. Firebase/Twilio wiring is a later step.
- Sessions are bearer tokens (`Authorization: Bearer …`), 30 days.

`enc_pubkey` is the user's X25519 public key (base64, 32 bytes), generated
on the device at signup. Private keys never leave the device.

## API summary

- `GET /me` — own profile (never returns phone/wallet values, only
  `has_phone` / `has_wallet` flags)
- `POST /me/cashtag {new_cashtag}` — rename; old $name is released, the
  change is recorded. `GET /me/cashtag-history` — full change record;
  profile field `cashtag_changed_at` powers "username last changed …"
- `POST /me/wallet/link` — link a wallet to an existing account
- `GET /users/lookup?cashtag=dexter` — public profile + presence by $name
- `GET/POST /contacts`, `DELETE /contacts/{cashtag}`
- `POST /groups {name, members: [$names]}` — group key distribution is
  client-side: the creator sends the group secretbox key to each member
  inside a normal 1-to-1 encrypted message; the server only fans out
  ciphertext
- `POST /messages` (REST) or WebSocket `send` frames — store-and-forward
  ciphertext; `ttl_seconds` sets the self-destruct timer
- `GET /messages/pending`, `POST /messages/ack` — offline queue
- `POST /blobs {kind: photo|voice, ciphertext, nonce, recipients|group_id,
  view_limit?, ttl_seconds?}` — encrypted blob upload. Photos can carry a
  **view limit**: each recipient fetch counts; when the limit is reached
  the blob is deleted server-side. `GET /blobs/{id}` enforces access,
  view counting, and expiry (410 once gone)

## WebSocket protocol (`/ws`)

First frame: `{"type":"auth","token":"…"}` → `auth_ok`, then any queued
messages as `{"type":"message","message":{…}}`.

Client → server: `{"type":"send","to_cashtag":"bob","ciphertext":"…",
"nonce":"…","ttl_seconds":60,"client_ref":"c1"}` (or `"group_id": 3`),
`{"type":"ack","message_id":123}`, `{"type":"ping"}`.

Server → client: `message`, `sent`, `expired` (a self-destruct timer fired),
`presence` (online/offline + last_seen), `pong`, `error`.

## Tests

```bash
.venv/bin/python -m pytest server/tests -v
```

The smoke tests boot a real server subprocess and drive it with a Python
reference client (`server/tests/refclient.py`) — the same NaCl wire format
the Flutter app uses.
