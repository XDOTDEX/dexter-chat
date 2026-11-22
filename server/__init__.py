"""DexterChat server — private, invite-only, E2E-encrypted messaging backend.

The server is deliberately dumb about content: it relays and stores ONLY
ciphertext (NaCl box / secretbox). It can never read message plaintext.
"""
