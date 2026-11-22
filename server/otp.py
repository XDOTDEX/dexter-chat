"""Phone-OTP delivery, behind a provider interface.

Phase 1 ships only a development provider that logs the code on the
server (and, in dev mode, the API returns it so the flow can be tested
end-to-end). A real provider (Firebase Auth / Twilio Verify / local SMS
gateway) implements `OtpProvider.send()` later — no account for any of
those is created in this phase.
"""
import logging
from abc import ABC, abstractmethod

log = logging.getLogger("otp")


class OtpProvider(ABC):
    @abstractmethod
    def send(self, phone: str, code: str) -> None:
        """Deliver `code` to `phone`. Raise on failure."""
        raise NotImplementedError


class DevLogOtpProvider(OtpProvider):
    """Dev-only provider: writes the code to the server log."""

    def send(self, phone: str, code: str) -> None:
        log.warning("DEV OTP for %s: %s", phone, code)


def get_provider() -> OtpProvider:
    # Later: pick Firebase/Twilio from env. For now there is only the stub.
    return DevLogOtpProvider()
