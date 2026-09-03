from decimal import Decimal
from typing import Optional

import strawberry
from django.conf import settings
from django.contrib.auth import authenticate
from django.db import transaction
from graphql import GraphQLError

from .. import models
from ..services.blockchain import BlockchainError, get_blockchain_service
from ..services.digilocker import DigiLockerError, get_digilocker_service
from ..services.hashing import compute_event_hash
from ..services.qrcode_service import make_qr_content_file
from .auth import create_token
from .permissions import require_owns_apiary, require_owns_batch, require_role
from .types import (
    ApiaryType,
    AuthPayload,
    DigilockerVerificationStart,
    HiveType,
    HoneyBatchType,
    apiary_type,
    honey_batch_type,
    to_hive_type,
    user_type,
)


def _get_batch_or_404(batch_id: str) -> models.HoneyBatch:
    try:
        return models.HoneyBatch.objects.get(batch_id=batch_id)
    except models.HoneyBatch.DoesNotExist:
        raise GraphQLError(f"Batch {batch_id} not found")


def _record_batch_event(batch, event_type: str, actor, event_data: dict) -> models.BatchEvent:
    """Writes the BatchEvent row (chain_status=PENDING), then anchors it
    on-chain. On failure the row is left in place (chain_status=FAILED) for
    retry/debugging rather than silently dropped -- blockchain confirmation
    is core to this product's value, so a failure is surfaced loudly."""
    data_hash = compute_event_hash(batch.batch_id, event_type, event_data)
    with transaction.atomic():
        event = models.BatchEvent.objects.create(
            batch=batch, event_type=event_type, actor=actor, event_data=event_data, data_hash=data_hash
        )

    chain = get_blockchain_service()
    try:
        tx_hash, block_number, chain_event_index = chain.record_event_onchain(batch.batch_id, event_type, data_hash)
    except BlockchainError as exc:
        event.chain_status = models.BatchEvent.ChainStatus.FAILED
        event.save(update_fields=["chain_status"])
        raise GraphQLError(f"Recorded in the database, but blockchain confirmation failed: {exc}")

    event.tx_hash = tx_hash
    event.block_number = block_number
    event.chain_event_index = chain_event_index
    event.chain_status = models.BatchEvent.ChainStatus.CONFIRMED
    event.save(update_fields=["tx_hash", "block_number", "chain_event_index", "chain_status"])
    return event


@strawberry.type
class Mutation:
    # --- Auth ---

    @strawberry.mutation
    def register(self, info: strawberry.Info, username: str, email: str, password: str) -> AuthPayload:
        """Always creates a BEEKEEPER account -- no role argument is accepted
        from this public mutation, so there is no path to self-service admin
        access. Admins are created only via `manage.py seed_admin`."""
        if models.User.objects.filter(username=username).exists():
            raise GraphQLError("Username already taken")
        user = models.User.objects.create_user(
            username=username, email=email, password=password, role=models.User.Role.BEEKEEPER
        )
        return AuthPayload(token=create_token(user), user=user_type(user))

    @strawberry.mutation
    def login(self, info: strawberry.Info, username: str, password: str) -> AuthPayload:
        user = authenticate(request=None, username=username, password=password)
        if user is None:
            raise GraphQLError("Invalid username or password")
        return AuthPayload(token=create_token(user), user=user_type(user))

    # --- Beekeeper: apiaries & hives ---

    @strawberry.mutation
    def create_apiary(self, info: strawberry.Info, name: str, location_description: str = "") -> ApiaryType:
        user = require_role(info, models.User.Role.BEEKEEPER)
        apiary = models.Apiary.objects.create(owner=user, name=name, location_description=location_description)
        return apiary_type(apiary)

    @strawberry.mutation
    def create_hive(self, info: strawberry.Info, apiary_id: strawberry.ID, label: str, hive_type: str = "") -> HiveType:
        user = require_role(info, models.User.Role.BEEKEEPER)
        try:
            apiary = models.Apiary.objects.get(pk=apiary_id)
        except models.Apiary.DoesNotExist:
            raise GraphQLError("Apiary not found")
        require_owns_apiary(user, apiary)
        hive = models.Hive.objects.create(apiary=apiary, label=label, hive_type=hive_type)
        return to_hive_type(hive)

    # --- Beekeeper: FSSAI / DigiLocker regulatory verification ---

    @strawberry.mutation
    def set_fssai_license_number(
        self, info: strawberry.Info, apiary_id: strawberry.ID, license_number: str
    ) -> ApiaryType:
        """Sets/edits the apiary's self-reported FSSAI license number.
        Always clears fssai_verified_at -- a verification only ever attests
        to the specific number it checked, so changing the number must
        invalidate any prior verified badge rather than silently keep it."""
        user = require_role(info, models.User.Role.BEEKEEPER)
        try:
            apiary = models.Apiary.objects.get(pk=apiary_id)
        except models.Apiary.DoesNotExist:
            raise GraphQLError("Apiary not found")
        require_owns_apiary(user, apiary)

        license_number = license_number.strip()
        if not license_number:
            raise GraphQLError("licenseNumber is required")

        apiary.fssai_license_number = license_number
        apiary.fssai_verified_at = None
        apiary.save(update_fields=["fssai_license_number", "fssai_verified_at"])
        return apiary_type(apiary)

    @strawberry.mutation
    def start_digilocker_verification(
        self, info: strawberry.Info, apiary_id: strawberry.ID
    ) -> DigilockerVerificationStart:
        """Kicks off the consent-redirect flow (see services/digilocker.py):
        the client opens the returned authorization_url in a new tab, the
        beekeeper grants (or denies) consent there, and
        digilocker_views.callback_view resolves the request and updates the
        apiary once they're done -- there's nothing more to return here,
        since the whole point of this flow is that the result arrives
        out-of-band, not from this mutation's response."""
        user = require_role(info, models.User.Role.BEEKEEPER)
        try:
            apiary = models.Apiary.objects.get(pk=apiary_id)
        except models.Apiary.DoesNotExist:
            raise GraphQLError("Apiary not found")
        require_owns_apiary(user, apiary)

        if not apiary.fssai_license_number:
            raise GraphQLError("Set an FSSAI license number before requesting verification")

        verification = models.DigilockerVerificationRequest.objects.create(
            apiary=apiary, requested_by=user, license_number=apiary.fssai_license_number
        )
        try:
            authorization_url = get_digilocker_service().build_authorization_url(str(verification.id))
        except DigiLockerError as exc:
            raise GraphQLError(f"Could not start DigiLocker verification: {exc}")

        return DigilockerVerificationStart(request_id=str(verification.id), authorization_url=authorization_url)

    # --- Beekeeper: batch creation + processing ---

    @strawberry.mutation
    def create_honey_batch(
        self,
        info: strawberry.Info,
        apiary_id: strawberry.ID,
        hive_ids: list[strawberry.ID],
        harvest_date: str,
        quantity_kg: float,
        floral_source: str,
    ) -> HoneyBatchType:
        import datetime

        user = require_role(info, models.User.Role.BEEKEEPER)
        try:
            apiary = models.Apiary.objects.get(pk=apiary_id)
        except models.Apiary.DoesNotExist:
            raise GraphQLError("Apiary not found")
        require_owns_apiary(user, apiary)

        hives = list(models.Hive.objects.filter(pk__in=hive_ids, apiary=apiary))
        if len(hives) != len(set(hive_ids)):
            raise GraphQLError("One or more hives were not found in this apiary")

        try:
            parsed_harvest_date = datetime.date.fromisoformat(harvest_date)
        except ValueError:
            raise GraphQLError("harvestDate must be an ISO date string (YYYY-MM-DD)")

        batch_id = models.HoneyBatch.generate_batch_id(on=parsed_harvest_date)
        with transaction.atomic():
            batch = models.HoneyBatch.objects.create(
                batch_id=batch_id,
                apiary=apiary,
                beekeeper=user,
                harvest_date=parsed_harvest_date,
                quantity_kg=Decimal(str(quantity_kg)),
                floral_source=floral_source,
            )
            batch.hives.set(hives)

        chain = get_blockchain_service()
        try:
            chain.create_batch_onchain(batch.batch_id, str(apiary.id))
        except BlockchainError as exc:
            raise GraphQLError(f"Batch created in the database, but on-chain registration failed: {exc}")

        _record_batch_event(
            batch,
            models.BatchEvent.EventType.HARVESTED,
            user,
            {
                "harvest_date": parsed_harvest_date.isoformat(),
                "quantity_kg": quantity_kg,
                "floral_source": floral_source,
                "hive_labels": [h.label for h in hives],
            },
        )
        batch.refresh_from_db()
        return honey_batch_type(batch)

    @strawberry.mutation
    def record_processing_event(self, info: strawberry.Info, batch_id: str, method: str, notes: str = "") -> HoneyBatchType:
        user = require_role(info, models.User.Role.BEEKEEPER)
        batch = _get_batch_or_404(batch_id)
        require_owns_batch(user, batch)
        if batch.status != models.HoneyBatch.Status.HARVESTED:
            raise GraphQLError(f"Batch must be HARVESTED to record processing (currently {batch.status})")

        _record_batch_event(
            batch, models.BatchEvent.EventType.PROCESSED, user, {"method": method, "notes": notes}
        )
        batch.status = models.HoneyBatch.Status.PROCESSED
        batch.save(update_fields=["status", "updated_at"])
        batch.refresh_from_db()
        return honey_batch_type(batch)

    # --- Admin: quality verification + packaging ---

    @strawberry.mutation
    def record_quality_check(
        self,
        info: strawberry.Info,
        batch_id: str,
        result: str,
        moisture_content: Optional[float] = None,
        purity_notes: str = "",
    ) -> HoneyBatchType:
        admin = require_role(info, models.User.Role.ADMIN)
        batch = _get_batch_or_404(batch_id)
        if batch.status != models.HoneyBatch.Status.PROCESSED:
            raise GraphQLError(f"Batch must be PROCESSED before a quality check (currently {batch.status})")
        if result not in models.QualityCheck.Result.values:
            raise GraphQLError(f"result must be one of {models.QualityCheck.Result.values}")

        event = _record_batch_event(
            batch,
            models.BatchEvent.EventType.QUALITY_CHECKED,
            admin,
            {"result": result, "moisture_content": moisture_content, "purity_notes": purity_notes},
        )
        models.QualityCheck.objects.create(
            batch=batch,
            reviewed_by=admin,
            moisture_content=Decimal(str(moisture_content)) if moisture_content is not None else None,
            purity_notes=purity_notes,
            result=result,
            linked_event=event,
        )
        if result == models.QualityCheck.Result.PASSED:
            batch.status = models.HoneyBatch.Status.QUALITY_CHECKED
            batch.save(update_fields=["status", "updated_at"])
        batch.refresh_from_db()
        return honey_batch_type(batch)

    @strawberry.mutation
    def package_batch(self, info: strawberry.Info, batch_id: str, package_code: str, unit_count: int = 1) -> HoneyBatchType:
        admin = require_role(info, models.User.Role.ADMIN)
        batch = _get_batch_or_404(batch_id)
        if batch.status != models.HoneyBatch.Status.QUALITY_CHECKED:
            raise GraphQLError(f"Batch must be QUALITY_CHECKED before packaging (currently {batch.status})")
        if models.Package.objects.filter(package_code=package_code).exists():
            raise GraphQLError("Package code already in use")

        event = _record_batch_event(
            batch,
            models.BatchEvent.EventType.PACKAGED,
            admin,
            {"package_code": package_code, "unit_count": unit_count},
        )

        public_url = f"{settings.PUBLIC_BASE_URL}/trace/{batch.batch_id}"
        qr_file = make_qr_content_file(public_url, filename=f"{batch.batch_id}.png")

        package = models.Package(
            batch=batch,
            package_code=package_code,
            unit_count=unit_count,
            public_url=public_url,
            packaged_by=admin,
            linked_event=event,
        )
        package.qr_code_image.save(qr_file.name, qr_file, save=False)
        package.save()

        batch.status = models.HoneyBatch.Status.PACKAGED
        batch.save(update_fields=["status", "updated_at"])
        batch.refresh_from_db()
        return honey_batch_type(batch)
