"""Runtime settings, all overridable by environment variables."""
import os

_HERE = os.path.dirname(os.path.abspath(__file__))


class Settings:
    def __init__(self) -> None:
        self.db_path = os.environ.get(
            "MSG_DB", os.path.join(_HERE, "data", "app.db"))
        # Key required for owner/admin actions (creating invite codes).
        self.admin_key = os.environ.get("MSG_ADMIN_KEY",
                                        "dev-admin-key-change-me")
        # Dev mode: the phone-OTP endpoint returns the code in the response
        # (and the provider just logs it). NEVER enable in production.
        self.dev_mode = os.environ.get("MSG_DEV_MODE", "1") == "1"
        self.host = os.environ.get("MSG_HOST", "127.0.0.1")
        self.port = int(os.environ.get("MSG_PORT", "8642"))

        self.otp_ttl = 300            # seconds a phone OTP stays valid
        self.otp_max_attempts = 5
        self.challenge_ttl = 300      # seconds a wallet nonce stays valid
        self.session_ttl = 60 * 60 * 24 * 30   # 30 days
        self.sweep_interval = float(os.environ.get("MSG_SWEEP_INTERVAL",
                                                   "1.0"))
        self.max_blob_bytes = 25 * 1024 * 1024  # 25 MB encrypted blob cap


settings = Settings()
