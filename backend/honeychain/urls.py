from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import path, re_path
from django.views.decorators.csrf import csrf_exempt

from traceability.digilocker_views import callback_view, mock_consent_view

from .flutter_spa_view import serve_flutter_app
from .graphql_view import AuthGraphQLView
from .schema import schema

urlpatterns = [
    path("admin/", admin.site.urls),
    path("graphql", csrf_exempt(AuthGraphQLView.as_view(schema=schema, graphql_ide="graphiql"))),
    path("digilocker/mock-consent", mock_consent_view),
    path("digilocker/callback", callback_view),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    # Catch-all, must stay last: serves the Flutter web build (with SPA
    # fallback) for anything not matched above. Lets Django alone serve the
    # whole app on one port -- see flutter_spa_view.py for why that matters.
    urlpatterns += [re_path(r"^(?P<path>.*)$", serve_flutter_app)]
