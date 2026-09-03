"""ApiSetuFssaiService tests -- requests.post is mocked throughout so the
suite doesn't depend on network access or the live sandbox being up; the
request/response shapes asserted here are pinned from real calls against
https://sandbox.api-setu.in made while building this integration (see
services/digilocker.py's docstrings for what those calls actually caught:
format="json" times out upstream, consentArtifact needs a non-blank
mobile or email, and its timestamps need millisecond+"Z" precision, not
Django's default isoformat())."""

import re
from unittest.mock import Mock, patch

from django.test import TestCase, override_settings

from traceability.services.digilocker import ApiSetuFssaiService, DigiLockerError


@override_settings(APISETU_API_KEY="demokey123456ABCD789", APISETU_CLIENT_ID="in.gov.sandbox", APISETU_FSSAI_ENDPOINT="recer")
class ApiSetuFssaiServiceTests(TestCase):
    def setUp(self):
        self.service = ApiSetuFssaiService()

    @patch("traceability.services.digilocker.requests.post")
    def test_200_means_verified(self, mock_post):
        mock_post.return_value = Mock(status_code=200)
        self.assertTrue(self.service.verify_license("12345678901234", email="a@b.com"))

    @patch("traceability.services.digilocker.requests.post")
    def test_404_means_not_verified_not_an_error(self, mock_post):
        mock_post.return_value = Mock(status_code=404, text='{"error":"record_not_found"}')
        self.assertFalse(self.service.verify_license("12345678901234", email="a@b.com"))

    @patch("traceability.services.digilocker.requests.post")
    def test_other_status_codes_raise_rather_than_return_false(self, mock_post):
        mock_post.return_value = Mock(status_code=401, text='{"error":"invalid_authentication"}')
        with self.assertRaises(DigiLockerError):
            self.service.verify_license("12345678901234", email="a@b.com")

    @patch("traceability.services.digilocker.requests.post")
    def test_network_failure_raises_digilocker_error(self, mock_post):
        import requests

        mock_post.side_effect = requests.ConnectionError("boom")
        with self.assertRaises(DigiLockerError):
            self.service.verify_license("12345678901234", email="a@b.com")

    @patch("traceability.services.digilocker.requests.post")
    def test_request_uses_xml_format_and_falls_back_to_placeholder_email(self, mock_post):
        """format="json" was confirmed (against the live sandbox) to 504
        upstream -- this pins format="xml" so a future edit can't
        reintroduce that regression silently. Also pins the blank-email
        fallback, since API Setu 400s when both mobile and email are
        blank."""
        mock_post.return_value = Mock(status_code=404, text="{}")
        self.service.verify_license("12345678901234")

        _, kwargs = mock_post.call_args
        body = kwargs["json"]
        self.assertEqual(body["format"], "xml")
        self.assertEqual(body["certificateParameters"]["licenseNo"], "12345678901234")
        self.assertTrue(body["consentArtifact"]["consent"]["user"]["email"])
        # Confirmed against the live sandbox: it 400s ("Invalid datetime
        # format for parameter: timestamp") on anything but millisecond
        # precision + a literal "Z" -- e.g. Django's timezone.now().isoformat()
        # (microseconds + "+00:00") fails this.
        timestamp_re = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
        self.assertRegex(body["consentArtifact"]["consent"]["timestamp"], timestamp_re)
        self.assertEqual(kwargs["headers"]["X-APISETU-APIKEY"], "demokey123456ABCD789")
        self.assertEqual(kwargs["headers"]["X-APISETU-CLIENTID"], "in.gov.sandbox")
        self.assertIn("/certificate/v3/fssai/recer", mock_post.call_args[0][0])

    def test_build_authorization_url_points_at_own_consent_page(self):
        url = self.service.build_authorization_url("some-request-id")
        self.assertIn("/digilocker/mock-consent", url)
        self.assertIn("request_id=some-request-id", url)


class ApiSetuFssaiServiceConfigTests(TestCase):
    @override_settings(APISETU_API_KEY="", APISETU_CLIENT_ID="")
    def test_missing_credentials_raise_on_construction(self):
        with self.assertRaises(DigiLockerError):
            ApiSetuFssaiService()

    @override_settings(
        APISETU_API_KEY="demokey123456ABCD789", APISETU_CLIENT_ID="in.gov.sandbox", APISETU_FSSAI_ENDPOINT="bogus"
    )
    def test_unknown_endpoint_choice_raises_on_construction(self):
        with self.assertRaises(DigiLockerError):
            ApiSetuFssaiService()
