"""Small security helpers: random tokens/codes and hashing."""
import hashlib
import secrets


def sha256_hex(data: str) -> str:
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def new_session_token() -> str:
    return secrets.token_urlsafe(32)


def new_invite_code() -> str:
    # e.g. "DX-7K3F9Q2A" — easy to read out / type on a phone.
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    body = "".join(secrets.choice(alphabet) for _ in range(8))
    return f"DX-{body}"


def new_nonce() -> str:
    return secrets.token_hex(16)


def new_otp_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"
