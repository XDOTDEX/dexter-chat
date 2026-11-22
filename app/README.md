# DexterChat app (Flutter)

Dark void-themed Flutter client for the DexterChat server. One APK,
**minSdk 23 (Android 6.0+)** so it runs on ~99% of devices.

## Run / analyze / test

```bash
flutter pub get
flutter analyze
flutter test          # includes PyNaCl cross-compat crypto vectors
flutter run           # emulator reaches the host server at 10.0.2.2:8642
```

Set the server URL on the login screen (or later in Profile) — for a real
phone it must be the server's LAN/public address, not 10.0.2.2.

## How it fits together

- `lib/services/crypto.dart` — X25519 identity + NaCl box/secretbox
  (pinenacl, a TweetNaCl port). Byte-compatible with the Python reference
  client; `test/crypto_test.dart` proves it against PyNaCl vectors.
- `lib/services/wallet.dart` — EVM login: the wallet private key is
  imported into the app and kept in the platform keystore
  (flutter_secure_storage); login = `personal_sign` of the server nonce.
  WalletConnect is a later phase. The address is never displayed.
- `lib/services/store.dart` — session, WebSocket relay, send/receive,
  group-key distribution, local history (JSON in the app sandbox;
  keys in secure storage).
- `lib/screens/photo_viewer.dart` — sets `FLAG_SECURE` via the
  `dexter/secure` method channel (see `MainActivity.kt`) while a
  view-limited photo is open.

## Phase-1 limitations (known, deliberate)

- Keys live on one device: no multi-device sync or key backup yet —
  resetting the device forgets the identity key and old messages can no
  longer be decrypted.
- No push notifications: new messages arrive while the app is open or via
  the server queue on next launch.
- Phone OTP uses the server's dev provider until Firebase is wired.
