from graphql import GraphQLError

from ..models import User


def current_user(info):
    """Returns the authenticated User, or None. Never raises."""
    return getattr(info.context.request, "hc_user", None)


def require_authenticated(info):
    user = current_user(info)
    if user is None:
        raise GraphQLError("Authentication required")
    return user


def require_role(info, role: str):
    user = require_authenticated(info)
    if user.role != role:
        raise GraphQLError(f"{role.title()} role required")
    return user


def require_owns_apiary(user, apiary):
    if apiary.owner_id != user.id and user.role != User.Role.ADMIN:
        raise GraphQLError("You do not have access to this apiary")


def require_owns_batch(user, batch):
    if batch.beekeeper_id != user.id and user.role != User.Role.ADMIN:
        raise GraphQLError("You do not have access to this batch")
