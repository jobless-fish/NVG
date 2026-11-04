"""Local web server for the Godot web build (build/web).

- Serves .wasm as application/wasm
- Sends `Cache-Control: no-store` so the browser never mixes an old index.pck/index.wasm
  with a new build (a mismatch makes the Godot loading screen hang forever).

Usage: python tools/serve_web.py [port]
"""
import functools
import http.server
import os
import sys
import webbrowser

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 8060


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".pck": "application/octet-stream", ".js": "text/javascript"}

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Expires", "0")
        super().end_headers()


if __name__ == "__main__":
    if not os.path.exists(os.path.join(ROOT, "index.html")):
        sys.exit("build/web/index.html not found - export the 'Web' preset first")
    handler = functools.partial(NoCacheHandler, directory=ROOT)
    with http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler) as httpd:
        url = "http://localhost:%d/index.html" % PORT
        print("Serving", ROOT, "at", url, "(Ctrl+C to stop)")
        if "--no-browser" not in sys.argv:
            webbrowser.open(url)
        httpd.serve_forever()
