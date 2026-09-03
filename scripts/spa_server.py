#!/usr/bin/env python3
"""Serves a Flutter web build (client/build/web) with SPA fallback: any
request path that isn't an actual file on disk gets index.html instead of
a 404. Flutter's client-side router (go_router, using path URL strategy --
see client/lib/main.dart's usePathUrlStrategy()) then reads the real path
out of the browser's address bar and renders the right screen itself.

Plain `python3 -m http.server` doesn't do this: a fresh load of a deep
link like /trace/HC-2026-0004 (exactly what scanning a QR code does) has
no file at that path, so it 404s before Flutter's JS ever runs -- looks
like "file not found" to the visitor, not an app error. Client-side
*navigation* to the same route works fine either way, since that never
issues a new HTTP request; only a fresh load / external link does.

Usage: spa_server.py <directory> <port>
"""

import http.server
import os
import sys


def make_handler(root: str):
    class SpaHandler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root, **kwargs)

        def translate_path(self, path):
            # Drop query string/fragment before resolving to a filesystem path.
            clean = path.split("?", 1)[0].split("#", 1)[0]
            candidate = super().translate_path(clean)
            if os.path.isfile(candidate):
                return candidate
            return super().translate_path("/index.html")

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - - [%s] %s\n" % (self.address_string(), self.log_date_time_string(), fmt % args))

    return SpaHandler


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <directory> <port>", file=sys.stderr)
        sys.exit(1)
    root, port = sys.argv[1], int(sys.argv[2])
    handler = make_handler(root)
    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), handler)
    print(f"Serving {root} on 0.0.0.0:{port} with SPA fallback")
    server.serve_forever()


if __name__ == "__main__":
    main()
