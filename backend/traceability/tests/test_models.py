import datetime
from decimal import Decimal

from django.test import TestCase

from traceability.models import Apiary, BatchEvent, DigilockerVerificationRequest, Hive, HoneyBatch, User
from traceability.services.digilocker import MockDigiLockerService


class ModelSmokeTests(TestCase):
    """Cheap sanity checks that the model layer + migrations are wired up
    correctly. Full functional coverage of the batch lifecycle happens via
    the GraphQL + on-chain smoke tests in later milestones."""

    def setUp(self):
        self.beekeeper = User.objects.create_user(
            username="alice", password="pw12345!", role=User.Role.BEEKEEPER
        )
        self.admin = User.objects.create_user(
            username="root-admin", password="pw12345!", role=User.Role.ADMIN, is_staff=True
        )

    def test_user_default_role_is_beekeeper(self):
        plain_user = User.objects.create_user(username="bob", password="pw12345!")
        self.assertEqual(plain_user.role, User.Role.BEEKEEPER)

    def test_apiary_and_hive_relationship(self):
        apiary = Apiary.objects.create(owner=self.beekeeper, name="Sunny Meadow")
        hive = Hive.objects.create(apiary=apiary, label="Hive-01")
        self.assertEqual(hive.apiary, apiary)
        self.assertIn(hive, apiary.hives.all())

    def test_batch_id_generation_is_sequential_per_year(self):
        first = HoneyBatch.generate_batch_id(on=datetime.date(2026, 1, 1))
        self.assertEqual(first, "HC-2026-0001")

        apiary = Apiary.objects.create(owner=self.beekeeper, name="Sunny Meadow")
        HoneyBatch.objects.create(
            batch_id=first,
            apiary=apiary,
            beekeeper=self.beekeeper,
            harvest_date=datetime.date(2026, 1, 1),
            quantity_kg=Decimal("10.00"),
            floral_source="Wildflower",
        )
        second = HoneyBatch.generate_batch_id(on=datetime.date(2026, 6, 1))
        self.assertEqual(second, "HC-2026-0002")

    def test_batch_defaults_to_harvested_status_and_events_are_ordered(self):
        apiary = Apiary.objects.create(owner=self.beekeeper, name="Sunny Meadow")
        batch = HoneyBatch.objects.create(
            batch_id="HC-2026-0099",
            apiary=apiary,
            beekeeper=self.beekeeper,
            harvest_date=datetime.date(2026, 1, 1),
            quantity_kg=Decimal("5.50"),
            floral_source="Clover",
        )
        self.assertEqual(batch.status, HoneyBatch.Status.HARVESTED)

        BatchEvent.objects.create(
            batch=batch, event_type=BatchEvent.EventType.HARVESTED, actor=self.beekeeper, data_hash="0x" + "0" * 64
        )
        BatchEvent.objects.create(
            batch=batch, event_type=BatchEvent.EventType.PROCESSED, actor=self.beekeeper, data_hash="0x" + "1" * 64
        )
        event_types = list(batch.events.values_list("event_type", flat=True))
        self.assertEqual(event_types, [BatchEvent.EventType.HARVESTED, BatchEvent.EventType.PROCESSED])

    def test_apiary_starts_fssai_unverified(self):
        apiary = Apiary.objects.create(owner=self.beekeeper, name="Sunny Meadow")
        self.assertEqual(apiary.fssai_license_number, "")
        self.assertIsNone(apiary.fssai_verified_at)

    def test_digilocker_verification_request_defaults_to_pending(self):
        apiary = Apiary.objects.create(owner=self.beekeeper, name="Sunny Meadow", fssai_license_number="12345678901234")
        req = DigilockerVerificationRequest.objects.create(
            apiary=apiary, requested_by=self.beekeeper, license_number=apiary.fssai_license_number
        )
        self.assertEqual(req.status, DigilockerVerificationRequest.Status.PENDING)
        self.assertIsNone(req.resolved_at)


class MockDigiLockerServiceTests(TestCase):
    """The mock provider is what stands in for a real aggregator (Setu,
    Sandbox.co.in, etc.) in this MVP -- worth pinning its format check
    directly, since it's the one piece of "verification" logic that
    actually exists today."""

    def setUp(self):
        self.service = MockDigiLockerService()

    def test_accepts_valid_14_digit_fssai_number(self):
        self.assertTrue(self.service.verify_license("12345678901234"))

    def test_rejects_wrong_length(self):
        self.assertFalse(self.service.verify_license("123"))

    def test_rejects_non_numeric(self):
        self.assertFalse(self.service.verify_license("1234567890ABCD"))

    def test_authorization_url_points_at_mock_consent_endpoint(self):
        url = self.service.build_authorization_url("some-request-id")
        self.assertIn("/digilocker/mock-consent", url)
        self.assertIn("request_id=some-request-id", url)
