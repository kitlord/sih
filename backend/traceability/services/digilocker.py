"""FSSAI license verification for an apiary, via API Setu.

Real integration here does NOT go through DigiLocker's own "Requester"
OAuth flow -- that requires formal Authorized Partner empanelment (or a
paid aggregator like Setu.co/Sandbox.co.in), out of reach for this
project. Instead it goes through **API Setu** (apisetu.gov.in), the
official government API exchange run by NIC/MeitY: its FSSAI collection
exposes the same underlying DigiLocker-backed verification as a direct,
synchronous POST -- license number in, verified/not-verified back, no
redirect or authorization-code exchange. The sandbox
(sandbox.api-setu.in) ships a working public demo key that anyone can
call immediately, no signup -- that's what this defaults to. See
https://sandbox.api-setu.in/api-collection/fssai for the live docs.

A *personal* API Setu key is a separate, heavier thing: sandbox.api-setu.in
itself has no signup at all (it's just the shared demo-key playground);
registering your own requires a "Partner" account at
partners.apisetu.gov.in, which signs you in via a real DigiLocker
account and then asks you to identify an organization by GSTIN, PAN,
MSME/Udyam, or a *.gov.in/*.nic.in website -- built for registered
businesses and government bodies, not hackathon teams. Not needed here;
the shared demo key already works for the sandbox.

FSSAI has two certificate types, both colloquially called "the FSSAI
license number": a Registration Certificate (petty/small food businesses,
below the turnover threshold) and a (State/Central) Food Stuff License
(larger ones). Apiary.fssai_license_number doesn't distinguish between
them, so APISETU_FSSAI_ENDPOINT picks which one this deployment checks
against -- default "recer" (Registration Certificate), the tier most
individual beekeepers/apiaries are likely to hold.

DIGILOCKER_USE_MOCK=True (the default) swaps in MockDigiLockerService,
which serves its own consent page (traceability/digilocker_views.py)
instead of calling out to API Setu at all. Both providers share the same
two-method shape, so swapping to the real one is a config change
(DIGILOCKER_USE_MOCK=False, optionally APISETU_API_KEY/APISETU_CLIENT_ID
if not using the public demo credentials), not a rewrite of anything that
calls get_digilocker_service().
"""

import logging
import uuid

import requests
from django.conf import settings
from django.utils import timezone

logger = logging.getLogger(__name__)


class DigiLockerError(Exception):
    """Raised when a DigiLocker/API Setu call fails or isn't configured."""


class ApiSetuFssaiService:
    """Real provider: calls API Setu's FSSAI verification endpoint
    directly. Not an OAuth adapter -- there's no authorization step to
    exchange a code for, so verify_license() does the whole job in one
    request."""

    ENDPOINT_PATHS = {
        "recer": "certificate/v3/fssai/recer",  # Registration Certificate (petty/small FBOs)
        "fslcs": "certificate/v3/fssai/fslcs",  # Food Stuff License (larger FBOs)
    }

    def __init__(self):
        if not settings.APISETU_API_KEY or not settings.APISETU_CLIENT_ID:
            raise DigiLockerError(
                "DIGILOCKER_USE_MOCK is False but APISETU_API_KEY/APISETU_CLIENT_ID are set to "
                "empty strings -- either unset them to fall back to the public sandbox demo "
                "credentials, or set them to your own (see settings.py's APISETU_* comments; a "
                "real key means registering as an API Setu partner at partners.apisetu.gov.in, "
                "which needs a GSTIN/PAN/MSME/gov.in identity -- not needed for the sandbox)."
            )
        try:
            path = self.ENDPOINT_PATHS[settings.APISETU_FSSAI_ENDPOINT]
        except KeyError:
            raise DigiLockerError(
                f"APISETU_FSSAI_ENDPOINT must be one of {list(self.ENDPOINT_PATHS)}, "
                f"got {settings.APISETU_FSSAI_ENDPOINT!r}"
            )
        self._url = f"{settings.APISETU_BASE_URL.rstrip('/')}/{path}"

    def build_authorization_url(self, request_id: str) -> str:
        """API Setu has no redirect/consent step of its own -- the request
        just needs a consentArtifact attached (see verify_license below).
        This still points at our own consent page: that's genuinely the
        right place to capture the beekeeper's yes/no *before* this
        backend queries a government registry on their behalf, real
        provider or not."""
        return f"{settings.BACKEND_BASE_URL}/digilocker/mock-consent?request_id={request_id}"

    def verify_license(self, license_number: str, email: str = "") -> bool:
        """POSTs to API Setu. 200 means the registry has a matching
        record -> verified. 404 record_not_found is the normal "no such
        license" outcome, not a failure -> not verified. Anything else
        (401/400/5xx, a timeout, a connection error) means the *call*
        failed, which is raised as a DigiLockerError rather than swallowed
        into a silent False -- a broken integration shouldn't look
        identical to an honest "not verified" to the beekeeper.

        format="xml" (not "json") -- confirmed against the live sandbox;
        API Setu hung/didn't respond within a reasonable time on
        format="json" during testing, so this deliberately doesn't use it
        even though it'd be more convenient. The response body isn't
        parsed either way since only the status code is used here.

        email is required by API Setu's consentArtifact (it 400s with
        "Either mobile or email is required" if both are blank) -- there's
        no mobile number in this app's data model, so a blank/missing
        beekeeper email falls back to a placeholder rather than failing
        the whole verification over a missing contact field.

        The timestamp fields need millisecond precision with a literal
        "Z" suffix (e.g. "2024-12-03T11:07:33.974Z") -- confirmed against
        the live sandbox, which 400s ("Invalid datetime format for
        parameter: timestamp") on Django's default
        timezone.now().isoformat(), which instead gives microseconds and
        a "+00:00" offset."""
        now_dt = timezone.now()
        now = now_dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now_dt.microsecond // 1000:03d}Z"
        body = {
            "txnId": str(uuid.uuid4()),
            "format": "xml",
            "certificateParameters": {"licenseNo": license_number},
            "consentArtifact": {
                "consent": {
                    "consentId": str(uuid.uuid4()),
                    "timestamp": now,
                    "dataConsumer": {"id": "honeychain"},
                    "dataProvider": {"id": "fssai"},
                    "purpose": {"description": "FSSAI license verification for HoneyChain apiary registration"},
                    "user": {
                        "idType": "FSSAI_LICENSE",
                        "idNumber": license_number,
                        "mobile": "",
                        "email": email.strip() or "beekeeper@honeychain.app",
                    },
                    "data": {"id": "fssai-certificate"},
                    "permission": {
                        "access": "READ",
                        "dateRange": {"from": now, "to": now},
                        "frequency": {"unit": "ONCE", "value": 1, "repeats": 0},
                    },
                },
                "signature": {"signature": ""},
            },
        }
        headers = {
            "X-APISETU-APIKEY": settings.APISETU_API_KEY,
            "X-APISETU-CLIENTID": settings.APISETU_CLIENT_ID,
            "Content-Type": "application/json",
        }
        try:
            response = requests.post(self._url, json=body, headers=headers, timeout=15)
        except requests.RequestException as exc:
            logger.warning("API Setu FSSAI call to %s failed: %s", self._url, exc)
            raise DigiLockerError(f"Could not reach API Setu: {exc}")

        # INFO, not DEBUG: this is the one line of evidence, visible in the
        # dev server's normal console output, that a given check actually
        # hit the live government API rather than a mock -- worth being
        # able to point at during a demo without turning on debug logging.
        logger.info(
            "API Setu FSSAI check (%s, txn %s): HTTP %s from %s",
            settings.APISETU_FSSAI_ENDPOINT,
            body["txnId"],
            response.status_code,
            self._url,
        )
        if response.status_code == 200:
            return True
        if response.status_code == 404:
            return False
        raise DigiLockerError(f"API Setu returned {response.status_code}: {response.text[:300]}")


class MockDigiLockerService:
    """Stands in for ApiSetuFssaiService during development/demo -- same
    two-method shape (authorization URL -> consent -> verify), just
    without a real registry behind it."""

    def build_authorization_url(self, request_id: str) -> str:
        return f"{settings.BACKEND_BASE_URL}/digilocker/mock-consent?request_id={request_id}"

    def verify_license(self, license_number: str, email: str = "") -> bool:
        """Mock "pull document + compare" step. FSSAI license numbers are a
        fixed 14-digit format -- checking that (rather than approving
        anything typed in) keeps the demo honest about what "verified" is
        actually supposed to mean, even though there's no real registry
        behind it yet. email is accepted (and ignored) only so this stays
        interchangeable with ApiSetuFssaiService.verify_license()."""
        digits = license_number.strip()
        return digits.isdigit() and len(digits) == 14


_instance = None


def get_digilocker_service():
    """Lazily-constructed module-level singleton, same pattern as
    services.blockchain.get_blockchain_service()."""
    global _instance
    if _instance is None:
        _instance = MockDigiLockerService() if settings.DIGILOCKER_USE_MOCK else ApiSetuFssaiService()
    return _instance
