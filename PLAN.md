# Own Messaging App — Plan

Status: BUILD STARTED 22 Nov ~14:55 at his word ("আপাতত পুরো অ্যাপস বিল্ড করা শুরু করে দাও") — full app, built in phases. Phase 1 = core (auth, $name registry, E2E chat, voice notes, view-limited photos, self-destruct).
Server deployment still deferred by him ("EC2 পরে") — the backend is built to run on any small server later.

## Publishing / distribution
- APK published on GitHub (Releases) AND on other similar services too (e.g. GitLab / Codeberg mirrors) — his instruction 22 Nov.
- Referral-link idea (accounts made via his referral link): raised by him 22 Nov and POSTPONED by him in the same breath ("ওটা থাক আপাতত") — NOT in the build; do not add it unprompted.

## What it is
- His own Telegram-like messaging app, PRIVATE use only — small circle, invite-only signup.
- Completely FREE for everyone, no paid tier. Total users: ~50–100 people max.
- Code + APK published via GitHub Releases (no Play Store). One Flutter APK.
- Must run on all Android versions: low minSdk (~Android 6/7, API 23/24) — covers ~99% of devices.

## Accounts & identity
- Login BOTH ways: wallet login AND phone-number OTP (Firebase free quota is enough at this scale).
- Every account has a username shown as **$username** (Cash App cashtag style). The $name IS the in-app address: people find, message, call and send by $name only.
- No "@" and no 0x wallet address is ever shown — the address stays hidden underneath, resolved by the app in the background (including for on-chain mode). Phone number not exposed either.
- **Username changes are tracked: the profile shows when the $username was last changed.**

## Secrecy — two modes (his hard requirement: conversations fully secret)
1. Default chat: end-to-end encrypted, carried over a decentralized network (XMTP/Waku-style) — no company server holding messages.
2. On-chain mode: a message sent as an actual encrypted transaction on chain — slower, costs gas, PERMANENT, cannot be deleted.
- **Encrypted chats get an auto-delete / self-destruct timer option, Telegram secret-chat style** (mode 1 only — mode 2 is permanent by design).

## Chat features (v1 targets)
- 1-to-1 and group chat, photo/file sharing, push notifications.
- **Voice messages (voice notes) sendable in chat.**
- **View-limited photos: when sending a photo, the sender selects how many times the recipient may open it (1 time, 2 times, ...); after the last view the photo disappears.** Telegram view-once style, but with a selectable count. Client-enforced inside the app; screenshots can't be fully prevented — same limitation as Telegram.
- Voice + video calls: WebRTC + coturn (TURN) on the server; LiveKit later if group calls are wanted.

## Offline mode
- Must also work with NO internet/data: mesh messaging (Bluetooth / Wi-Fi Direct, Briar-style) between nearby users.
- Limits (explained and accepted): nearby only, no long-distance delivery while offline; calls and on-chain mode still need internet.

## Server
- A NEW dedicated EC2 instance just for this app (nothing else on it), separate from bots-server, same AWS account.
- Wanted region: Singapore (ap-southeast-1) — BLOCKED by the free-plan region lock; nothing created. When server work resumes: separate instance in Sydney (allowed now) vs upgrading the plan for Singapore. t3.micro proposed to protect the free-plan credits.

## Open decisions
- Base: own Flutter MVP (proposed) vs ready-made (Matrix/Rocket.Chat) — MVP route proposed, demo not yet started.
- Which chain for on-chain mode.
- Telegram ecosystem route (custom client on TDLib using his existing DExTER api_id/api_hash): raised 22 Nov, SKIPPED by him for now — the standalone plan above stands; do not re-pitch unprompted.
