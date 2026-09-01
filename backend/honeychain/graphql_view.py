from strawberry.django.views import GraphQLView

from traceability.graphql.auth import decode_token
from traceability.models import User


class AuthGraphQLView(GraphQLView):
    """Parses `Authorization: Bearer <jwt>` and attaches the resolved user
    (or None) onto the request as `hc_user`, read by
    traceability.graphql.permissions helpers in every resolver."""

    def get_context(self, request, response):
        context = super().get_context(request, response)
        context.request.hc_user = self._authenticate(request)
        return context

    @staticmethod
    def _authenticate(request):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        token = header.removeprefix("Bearer ").strip()
        payload = decode_token(token)
        if not payload:
            return None
        try:
            return User.objects.get(pk=payload["user_id"])
        except User.DoesNotExist:
            return None
