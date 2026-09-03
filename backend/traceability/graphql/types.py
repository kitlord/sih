"""GraphQL types, hand-written (no auto-CRUD layer) and mapped from Django
model instances via the `*_type()` functions below. Mapping is eager (a
type's relations are resolved into plain lists at construction time) rather
than lazily-resolved per-field -- a deliberate simplicity trade-off that's
fine at this MVP's data scale; a production version would reach for
dataloaders to avoid over-fetching.
"""

import datetime
from typing import Optional

import strawberry
from strawberry.scalars import JSON

from .. import models
from ..services.blockchain import get_blockchain_service


@strawberry.type
class UserType:
    id: strawberry.ID
    username: str
    email: str
    role: str


def user_type(u: models.User) -> UserType:
    return UserType(id=strawberry.ID(str(u.id)), username=u.username, email=u.email, role=u.role)


@strawberry.type
class HiveType:
    id: strawberry.ID
    label: str
    hive_type: str
    is_active: bool
    created_at: datetime.datetime


def to_hive_type(h: models.Hive) -> HiveType:
    return HiveType(
        id=strawberry.ID(str(h.id)),
        label=h.label,
        hive_type=h.hive_type,
        is_active=h.is_active,
        created_at=h.created_at,
    )


@strawberry.type
class ApiaryType:
    id: strawberry.ID
    name: str
    location_description: str
    created_at: datetime.datetime
    hives: list[HiveType]
    fssai_license_number: str
    fssai_verified: bool
    fssai_verified_at: Optional[datetime.datetime]


def apiary_type(a: models.Apiary) -> ApiaryType:
    return ApiaryType(
        id=strawberry.ID(str(a.id)),
        name=a.name,
        location_description=a.location_description,
        created_at=a.created_at,
        hives=[to_hive_type(h) for h in a.hives.all()],
        fssai_license_number=a.fssai_license_number,
        fssai_verified=a.fssai_verified_at is not None,
        fssai_verified_at=a.fssai_verified_at,
    )


@strawberry.type
class DigilockerVerificationStart:
    """Returned by startDigilockerVerification -- the Flutter client opens
    authorization_url in a new tab/window and lets the user complete
    consent there; there is no synchronous "is it done yet" response
    because the whole point of this flow is an out-of-band redirect."""

    request_id: str
    authorization_url: str


@strawberry.type
class BatchEventType:
    id: strawberry.ID
    event_type: str
    actor: UserType
    timestamp: datetime.datetime
    event_data: JSON
    data_hash: str
    tx_hash: Optional[str]
    block_number: Optional[int]
    chain_event_index: Optional[int]
    chain_status: str


def batch_event_type(e: models.BatchEvent) -> BatchEventType:
    return BatchEventType(
        id=strawberry.ID(str(e.id)),
        event_type=e.event_type,
        actor=user_type(e.actor),
        timestamp=e.timestamp,
        event_data=e.event_data,
        data_hash=e.data_hash,
        tx_hash=e.tx_hash,
        block_number=e.block_number,
        chain_event_index=e.chain_event_index,
        chain_status=e.chain_status,
    )


@strawberry.type
class QualityCheckType:
    id: strawberry.ID
    reviewed_by: UserType
    moisture_content: Optional[float]
    purity_notes: str
    result: str
    checked_at: datetime.datetime


def quality_check_type(q: models.QualityCheck) -> QualityCheckType:
    return QualityCheckType(
        id=strawberry.ID(str(q.id)),
        reviewed_by=user_type(q.reviewed_by),
        moisture_content=float(q.moisture_content) if q.moisture_content is not None else None,
        purity_notes=q.purity_notes,
        result=q.result,
        checked_at=q.checked_at,
    )


@strawberry.type
class PackageType:
    id: strawberry.ID
    package_code: str
    unit_count: int
    qr_code_url: str
    public_url: str
    # Authenticated surface only (HoneyBatchType.package, via `batch` /
    # `adminAllBatches` / `myBatches`) -- never exposed on PublicTraceType,
    # since anyone can load the public trace page. See Package.review_code.
    review_code: str
    packaged_by: UserType
    packaged_at: datetime.datetime


def package_type(p: models.Package) -> PackageType:
    from django.conf import settings

    return PackageType(
        id=strawberry.ID(str(p.id)),
        package_code=p.package_code,
        unit_count=p.unit_count,
        qr_code_url=f"{settings.BACKEND_BASE_URL}{p.qr_code_image.url}",
        public_url=p.public_url,
        review_code=p.review_code,
        packaged_by=user_type(p.packaged_by),
        packaged_at=p.packaged_at,
    )


@strawberry.type
class ReviewType:
    id: strawberry.ID
    rating: int
    comment: str
    reviewer_name: str
    submitted_at: datetime.datetime


def review_type(r: models.Review) -> ReviewType:
    return ReviewType(
        id=strawberry.ID(str(r.id)),
        rating=r.rating,
        comment=r.comment,
        reviewer_name=r.reviewer_name,
        submitted_at=r.submitted_at,
    )


@strawberry.type
class ApiaryRatingType:
    """One row of the admin-only ratings-by-location summary -- lets an
    admin see which apiaries are getting poor consumer feedback without
    opening every batch individually."""

    apiary: ApiaryType
    average_rating: Optional[float]
    review_count: int


@strawberry.type
class HoneyBatchType:
    id: strawberry.ID
    batch_id: str
    apiary: ApiaryType
    hives: list[HiveType]
    beekeeper: UserType
    harvest_date: datetime.date
    quantity_kg: float
    floral_source: str
    status: str
    created_at: datetime.datetime
    updated_at: datetime.datetime
    events: list[BatchEventType]
    quality_check: Optional[QualityCheckType]
    package: Optional[PackageType]


def honey_batch_type(b: models.HoneyBatch) -> HoneyBatchType:
    latest_check = b.quality_checks.order_by("-checked_at").first()
    package = getattr(b, "package", None)
    return HoneyBatchType(
        id=strawberry.ID(str(b.id)),
        batch_id=b.batch_id,
        apiary=apiary_type(b.apiary),
        hives=[to_hive_type(h) for h in b.hives.all()],
        beekeeper=user_type(b.beekeeper),
        harvest_date=b.harvest_date,
        quantity_kg=float(b.quantity_kg),
        floral_source=b.floral_source,
        status=b.status,
        created_at=b.created_at,
        updated_at=b.updated_at,
        events=[batch_event_type(e) for e in b.events.all()],
        quality_check=quality_check_type(latest_check) if latest_check else None,
        package=package_type(package) if package else None,
    )


@strawberry.type
class AuthPayload:
    token: str
    user: UserType


# --- Public (unauthenticated) consumer trace types ---


@strawberry.type
class PublicEventType:
    event_type: str
    timestamp: datetime.datetime
    event_data: JSON
    tx_hash: Optional[str]
    chain_status: str
    chain_verified: bool


@strawberry.type
class PublicTraceType:
    batch_id: str
    apiary_name: str
    location_description: str
    harvest_date: datetime.date
    hive_labels: list[str]
    quantity_kg: float
    floral_source: str
    status: str
    beekeeper_username: str
    events: list[PublicEventType]
    quality_result: Optional[str]
    quality_notes: Optional[str]
    package_code: Optional[str]
    packaged_at: Optional[datetime.datetime]
    all_events_chain_verified: bool
    fssai_license_number: str
    fssai_verified: bool
    reviews: list[ReviewType]
    average_rating: Optional[float]
    review_count: int


def public_trace_type(b: models.HoneyBatch) -> PublicTraceType:
    """Builds the consumer-facing provenance view, verifying every event's
    stored hash against the on-chain record live (not just trusting the
    Postgres row) -- this is the whole point of the public trace page."""
    chain = get_blockchain_service()

    public_events = []
    all_verified = True
    for e in b.events.all():
        verified = False
        if e.chain_event_index is not None:
            verified = chain.verify_hash(b.batch_id, e.chain_event_index, e.data_hash)
        all_verified = all_verified and verified
        public_events.append(
            PublicEventType(
                event_type=e.event_type,
                timestamp=e.timestamp,
                event_data=e.event_data,
                tx_hash=e.tx_hash,
                chain_status=e.chain_status,
                chain_verified=verified,
            )
        )

    latest_check = b.quality_checks.order_by("-checked_at").first()
    package = getattr(b, "package", None)

    reviews = list(b.reviews.all())
    review_count = len(reviews)
    average_rating = (sum(r.rating for r in reviews) / review_count) if review_count else None

    return PublicTraceType(
        batch_id=b.batch_id,
        apiary_name=b.apiary.name,
        location_description=b.apiary.location_description,
        harvest_date=b.harvest_date,
        hive_labels=[h.label for h in b.hives.all()],
        quantity_kg=float(b.quantity_kg),
        floral_source=b.floral_source,
        status=b.status,
        beekeeper_username=b.beekeeper.username,
        events=public_events,
        quality_result=latest_check.result if latest_check else None,
        quality_notes=latest_check.purity_notes if latest_check else None,
        package_code=package.package_code if package else None,
        packaged_at=package.packaged_at if package else None,
        all_events_chain_verified=all_verified and len(public_events) > 0,
        fssai_license_number=b.apiary.fssai_license_number,
        fssai_verified=b.apiary.fssai_verified_at is not None,
        reviews=[review_type(r) for r in reviews],
        average_rating=average_rating,
        review_count=review_count,
    )
