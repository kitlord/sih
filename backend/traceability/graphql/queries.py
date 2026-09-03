from typing import Optional

import strawberry
from django.db.models import Avg, Count, F
from graphql import GraphQLError

from .. import models
from .permissions import current_user, require_authenticated, require_role
from .types import (
    ApiaryRatingType,
    ApiaryType,
    HiveType,
    HoneyBatchType,
    PublicTraceType,
    UserType,
    apiary_type,
    honey_batch_type,
    to_hive_type,
    public_trace_type,
    user_type,
)


@strawberry.type
class Query:
    @strawberry.field
    def me(self, info: strawberry.Info) -> Optional[UserType]:
        user = current_user(info)
        return user_type(user) if user else None

    @strawberry.field
    def my_apiaries(self, info: strawberry.Info) -> list[ApiaryType]:
        user = require_role(info, models.User.Role.BEEKEEPER)
        return [apiary_type(a) for a in models.Apiary.objects.filter(owner=user)]

    @strawberry.field
    def my_hives(self, info: strawberry.Info, apiary_id: Optional[strawberry.ID] = None) -> list[HiveType]:
        user = require_role(info, models.User.Role.BEEKEEPER)
        qs = models.Hive.objects.filter(apiary__owner=user)
        if apiary_id is not None:
            qs = qs.filter(apiary_id=apiary_id)
        return [to_hive_type(h) for h in qs]

    @strawberry.field
    def my_batches(self, info: strawberry.Info) -> list[HoneyBatchType]:
        user = require_role(info, models.User.Role.BEEKEEPER)
        return [honey_batch_type(b) for b in models.HoneyBatch.objects.filter(beekeeper=user)]

    @strawberry.field
    def batch(self, info: strawberry.Info, batch_id: str) -> Optional[HoneyBatchType]:
        user = require_authenticated(info)
        try:
            b = models.HoneyBatch.objects.get(batch_id=batch_id)
        except models.HoneyBatch.DoesNotExist:
            return None
        if b.beekeeper_id != user.id and user.role != models.User.Role.ADMIN:
            raise GraphQLError("You do not have access to this batch")
        return honey_batch_type(b)

    @strawberry.field
    def admin_all_batches(self, info: strawberry.Info, status: Optional[str] = None) -> list[HoneyBatchType]:
        require_role(info, models.User.Role.ADMIN)
        qs = models.HoneyBatch.objects.all()
        if status:
            qs = qs.filter(status=status)
        return [honey_batch_type(b) for b in qs]

    @strawberry.field
    def admin_apiary_ratings(self, info: strawberry.Info) -> list[ApiaryRatingType]:
        """Average consumer rating per apiary (across all its batches'
        reviews), worst-rated first -- gives an admin a single view of
        which locations/beekeepers are getting poor feedback, without
        opening every batch individually. Apiaries with no reviews yet
        sort last (averageRating is null), not first."""
        require_role(info, models.User.Role.ADMIN)
        apiaries = models.Apiary.objects.annotate(
            avg_rating=Avg("batches__reviews__rating"),
            rating_count=Count("batches__reviews"),
        ).order_by(F("avg_rating").asc(nulls_last=True))
        return [
            ApiaryRatingType(apiary=apiary_type(a), average_rating=a.avg_rating, review_count=a.rating_count)
            for a in apiaries
        ]

    @strawberry.field
    def public_trace_by_batch_id(self, info: strawberry.Info, batch_id: str) -> Optional[PublicTraceType]:
        """No authentication required -- this is the only query the public
        consumer /trace/<batchId> page uses. Only packaged batches are
        visible here (a batch only ever gets a QR/public URl once packaged),
        so an in-progress batch can't be discovered by guessing its id."""
        try:
            b = models.HoneyBatch.objects.get(batch_id=batch_id, status=models.HoneyBatch.Status.PACKAGED)
        except models.HoneyBatch.DoesNotExist:
            return None
        return public_trace_type(b)
