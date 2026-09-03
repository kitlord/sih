"""DigiLocker "Requester"-side verification of an apiary's FSSAI license.

Real DigiLocker integration for an app like this means becoming a
Requester and going through an OAuth2-style consent-redirect flow: the
backend builds an authorization URL, the beekeeper grants consent on
DigiLocker's own site (or a licensed aggregator's, e.g. Setu or
Sandbox.co.in -- going direct to MeitY requires formal Authorized Partner
empanelment, out of reach for this project), and gets redirected back to a
callback URL here with a code that's exchanged for the verified document.

No aggregator account exists for this MVP, so DIGILOCKER_USE_MOCK=True (the
default) swaps in MockDigiLockerService, which serves its own consent page
(traceability/digilocker_views.py) instead of a real DigiLocker login --
same redirect-based shape, so swapping in a real provider later is a config
change (DIGILOCKER_USE_MOCK=False + DIGILOCKER_CLIENT_ID/
DIGILOCKER_CLIENT_SECRET pointed at a real aggregator), not a rewrite of
anything that calls get_digilocker_service().
"""

from django.conf import settings


class DigiLockerError(Exception):
    """Raised when a DigiLocker call fails or isn't configured."""


class DigiLockerService:
    """Real-provider adapter, shaped after aggregators like Setu /
    Sandbox.co.in. Not wired to a live account: fill in
    build_authorization_url()/verify_license() with that provider's actual
    OAuth + document-pull calls once DIGILOCKER_CLIENT_ID/SECRET are set."""

    def __init__(self):
        if not settings.DIGILOCKER_CLIENT_ID or not settings.DIGILOCKER_CLIENT_SECRET:
            raise DigiLockerError(
                "DIGILOCKER_USE_MOCK is False but DIGILOCKER_CLIENT_ID/DIGILOCKER_CLIENT_SECRET "
                "are not set -- point them at a real aggregator's credentials (e.g. Setu, Sandbox.co.in)."
            )

    def build_authorization_url(self, request_id: str) -> str:
        raise DigiLockerError("Real DigiLocker provider adapter is not implemented yet.")

    def verify_license(self, license_number: str) -> bool:
        raise DigiLockerError("Real DigiLocker provider adapter is not implemented yet.")


class MockDigiLockerService:
    """Stands in for a real aggregator sandbox during development/demo --
    same redirect-based shape (authorization URL -> consent -> callback) as
    the real thing, just served by this backend instead of DigiLocker."""

    def build_authorization_url(self, request_id: str) -> str:
        return f"{settings.BACKEND_BASE_URL}/digilocker/mock-consent?request_id={request_id}"

    def verify_license(self, license_number: str) -> bool:
        """Mock "pull document + compare" step. FSSAI license numbers are a
        fixed 14-digit format -- checking that (rather than approving
        anything typed in) keeps the demo honest about what "verified" is
        actually supposed to mean, even though there's no real registry
        behind it yet."""
        digits = license_number.strip()
        return digits.isdigit() and len(digits) == 14


_instance = None


def get_digilocker_service():
    """Lazily-constructed module-level singleton, same pattern as
    services.blockchain.get_blockchain_service()."""
    global _instance
    if _instance is None:
        _instance = MockDigiLockerService() if settings.DIGILOCKER_USE_MOCK else DigiLockerService()
    return _instance
