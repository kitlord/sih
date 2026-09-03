"""Serves the Flutter web build (client/build/web) from Django itself, with
SPA fallback -- same idea as scripts/spa_server.py, but as a Django view so
the whole app (GraphQL + media + the client UI) can live behind a single
port/origin. That matters specifically for exposing this over a tunnel
(ngrok etc.): one port means one tunnel, rather than needing two running
simultaneously (which a free ngrok plan's one-reserved-domain, session
limits make awkward) -- see scripts/dev_up.sh's --public mode.

Not used by --lan mode, which already has a working two-port setup (Django
on 8000, a separate static server on 8080) and has no such constraint.
"""

from pathlib import Path

from django.http import Http404
from django.views.static import serve

WEB_ROOT = Path(__file__).resolve().parent.parent.parent / "client" / "build" / "web"


def serve_flutter_app(request, path=""):
    if not WEB_ROOT.is_dir():
        raise Http404(
            "No Flutter web build found at client/build/web -- run "
            "`flutter build web` in client/ first."
        )
    candidate = (WEB_ROOT / path).resolve()
    # Path traversal guard: reject anything that resolves outside WEB_ROOT.
    if WEB_ROOT not in candidate.parents and candidate != WEB_ROOT:
        raise Http404
    if path and candidate.is_file():
        return serve(request, path, document_root=str(WEB_ROOT))
    # Any other path (client-side routes like /trace/<batchId>, or just a
    # cold load of "/") gets index.html; Flutter's own router (path URL
    # strategy -- see client/lib/main.dart's usePathUrlStrategy()) reads the
    # real path back out of the browser's address bar itself.
    return serve(request, "index.html", document_root=str(WEB_ROOT))
