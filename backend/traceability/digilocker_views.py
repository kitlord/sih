"""Plain Django views (not GraphQL) for the DigiLocker consent-redirect
flow. These have to be regular HTTP endpoints rather than GraphQL fields
because the whole point of the flow is a browser redirect out to a consent
page and back -- see services/digilocker.py for why.

mock_consent_view stands in for DigiLocker's own hosted consent page.
callback_view is what both the mock and (once configured) a real provider
redirect back to; it's the one place that actually resolves a
DigilockerVerificationRequest and updates the Apiary.
"""

import uuid

from django.http import HttpResponse, HttpResponseBadRequest, HttpResponseRedirect
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.html import escape

from .models import DigilockerVerificationRequest
from .services.digilocker import get_digilocker_service


def _parse_request_id(raw: str):
    """Validates the request_id looks like a UUID before it ever reaches
    the ORM -- a malformed value would otherwise raise inside
    get_object_or_404() as an uncaught ValueError (a 500), rather than the
    404/400 an unknown or garbled request_id should actually produce."""
    try:
        return uuid.UUID(raw)
    except (ValueError, AttributeError):
        return None


def mock_consent_view(request):
    """GET /digilocker/mock-consent?request_id=... -- a stand-in for the
    consent screen a real DigiLocker/aggregator login would show. Uses a
    GET form (not POST) so this stays outside Django's CSRF machinery,
    same as any other unauthenticated cross-site redirect target."""
    request_id = _parse_request_id(request.GET.get("request_id", ""))
    if request_id is None:
        return HttpResponseBadRequest("Invalid request_id")
    verification = get_object_or_404(
        DigilockerVerificationRequest.objects.select_related("apiary"), pk=request_id
    )

    if verification.status != DigilockerVerificationRequest.Status.PENDING:
        return HttpResponse(f"This request has already been resolved ({verification.status}).")

    apiary_name = escape(verification.apiary.name)
    license_number = escape(verification.license_number)
    callback_base = "/digilocker/callback"

    html = f"""<!doctype html>
<html><head><meta charset="utf-8"><title>Mock DigiLocker Consent</title>
<style>
  body {{ font-family: -apple-system, sans-serif; max-width: 440px; margin: 64px auto; text-align: center; color: #222; }}
  .badge {{ display: inline-block; padding: 4px 12px; border-radius: 999px; background: #fef3c7; color: #92400e;
            font-size: 12px; font-weight: 600; margin-bottom: 20px; }}
  h2 {{ margin: 0 0 8px; }}
  .detail {{ background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 10px; padding: 16px; margin: 20px 0; text-align: left; }}
  code {{ font-family: monospace; }}
  button {{ padding: 12px 28px; margin: 6px; font-size: 15px; font-weight: 600; border-radius: 8px; border: none; cursor: pointer; }}
  .approve {{ background: #16a34a; color: white; }}
  .deny {{ background: #dc2626; color: white; }}
</style></head>
<body>
  <div class="badge">MOCK DigiLocker &mdash; stands in for a real aggregator sandbox</div>
  <h2>Share FSSAI license?</h2>
  <p>An app is requesting to verify a license against DigiLocker on your behalf.</p>
  <div class="detail">
    <div><b>Apiary:</b> {apiary_name}</div>
    <div><b>FSSAI license:</b> <code>{license_number}</code></div>
  </div>
  <form method="get" action="{callback_base}">
    <input type="hidden" name="request_id" value="{verification.id}">
    <button class="approve" name="decision" value="approved">Approve</button>
    <button class="deny" name="decision" value="denied">Deny</button>
  </form>
</body></html>"""
    return HttpResponse(html)


def callback_view(request):
    """GET /digilocker/callback?request_id=...&decision=approved|denied --
    resolves the request and redirects the browser back into the Flutter
    app, same shape a real provider's OAuth callback would use (minus the
    authorization-code exchange, which MockDigiLockerService skips)."""
    from django.conf import settings

    request_id = _parse_request_id(request.GET.get("request_id", ""))
    decision = request.GET.get("decision", "")
    if request_id is None:
        return HttpResponseBadRequest("Invalid request_id")
    verification = get_object_or_404(
        DigilockerVerificationRequest.objects.select_related("apiary"), pk=request_id
    )

    if verification.status == DigilockerVerificationRequest.Status.PENDING:
        if decision == "approved":
            verified = get_digilocker_service().verify_license(verification.license_number)
            verification.status = (
                DigilockerVerificationRequest.Status.APPROVED
                if verified
                else DigilockerVerificationRequest.Status.DENIED
            )
            if verified:
                apiary = verification.apiary
                apiary.fssai_verified_at = timezone.now()
                apiary.save(update_fields=["fssai_verified_at"])
        else:
            verification.status = DigilockerVerificationRequest.Status.DENIED
        verification.resolved_at = timezone.now()
        verification.save(update_fields=["status", "resolved_at"])

    outcome = "verified" if verification.status == DigilockerVerificationRequest.Status.APPROVED else "failed"
    redirect_url = f"{settings.PUBLIC_BASE_URL}/beekeeper/apiaries/{verification.apiary_id}?digilocker={outcome}"
    return HttpResponseRedirect(redirect_url)
