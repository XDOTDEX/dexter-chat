# DexterChat — private messaging app (Phase 1)

The owner's own Telegram-like messenger: **private, invite-only, completely
free**, built for a small circle (~50–100 people). Spec: [PLAN.md](PLAN.md).

Phase 1 (this build) delivers the working core:

- **Accounts** — signup only with an owner-generated invite code.
  Login by **EVM wallet** (sign a server nonce, `personal_sign`) or by
  **phone OTP** (provider stubbed behind an interface; dev mode returns
  the code so the flow is testable — Firebase wiring is a later step).
- **Identity = $name** — cashtag-style handle (`$dexter`). It is the only
  address shown anywhere; wallet addresses and phone numbers never appear
  in any API response or screen. $name changes are recorded — profiles
  show "username last changed <date>" and keep the full history; the old
  $name is released for others.
- **End-to-end encrypted chat** — per-user X25519 keypairs; 1-to-1 messages
  use NaCl box, group messages a shared secretbox key distributed over the
  1-to-1 channels. The server stores/relays **ciphertext only** (proven by
  the smoke tests, which scan the raw DB for plaintext).
- **Voice notes** — recorded in-app, uploaded as encrypted blobs.
- **View-limited photos** — the sender picks how many times the recipient
  may open a photo (1, 2, 3…); the server counts views and deletes the
  blob at the limit. The viewer screen sets Android `FLAG_SECURE`
  (screenshot/screen-record blocked on the viewer's device).
- **Self-destruct timer** — per-message/per-chat option, Telegram
  secret-chat style; the server purges ciphertext at expiry and clients
  delete their local copies.

Not in Phase 1 (structured for, built later): voice/video calls, offline
mesh, on-chain mode, push notifications, referral system (postponed by the
owner — do not add).

## Layout

```
server/   FastAPI + SQLite backend (see server/README.md)
app/      Flutter app, minSdk 23 / Android 6+ (see app/README.md)
```

## Quick start (local)

```bash
python3 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
.venv/bin/python -m server.cli create-invite 3     # print invite codes
.venv/bin/python -m server                          # http://127.0.0.1:8642
.venv/bin/python -m pytest server/tests -v          # 10 smoke tests
```

Nothing is deployed and nothing is published yet — distribution (GitHub
Releases + mirrors) happens on the owner's word.

## Build status (22 Nov 2026)

- Server: 10/10 pytest smoke tests pass.
- App: `flutter analyze` clean (0 issues); `flutter test` 6/6 crypto
  cross-compat tests pass (Dart ↔ PyNaCl byte-for-byte).
- Toolchain installed on this VM: Flutter 3.50.1 (`~/flutter-sdk`),
  Temurin JDK 17 (`~/jdk`), Android SDK 36 + build-tools 36.0.0 + NDK
  28.2 (`~/android-sdk`, zip-installed), Gradle 9.5.0 distribution
  pre-seeded in `~/gradle-home` (use `GRADLE_USER_HOME=~/gradle-home`).
- **APK build is BLOCKED in this VM**: the sandbox intercepts direct TCP
  connections from Java processes (even 127.0.0.1 loopback) and answers
  "muse: Other TCP connections is turned off for this assistant", so
  Gradle's client↔daemon handshake fails with
  `DaemonConnectionException: Could not dispatch a message to the daemon`
  / `java.io.IOException: Broken pipe`. To unblock: in the Muse web app,
  Settings → Permissions → Direct network protocols → allow direct TCP,
  then run:
  `cd app && JAVA_HOME=~/jdk GRADLE_USER_HOME=~/gradle-home ~/flutter-sdk/bin/flutter build apk --debug`
  Expected output: `app/build/app/outputs/flutter-apk/app-debug.apk`.
  On any normal machine (or the owner's PC) the same command builds
  without this issue. Build logs: `build1.log`–`build5.log`.
