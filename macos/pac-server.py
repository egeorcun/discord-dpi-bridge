#!/usr/bin/python3
"""
discord-dpi-bridge / macOS - yerel PAC sunucusu

Sistem proxy ayari (networksetup -setautoproxyurl) bir URL ister. Chromium tabanli
uygulamalar (Discord) file:// PAC adreslerini kabul etmez; bu yuzden proxy.pac
127.0.0.1 uzerinden kucuk bir HTTP sunucusuyla verilir. Yalnizca loopback'te dinler,
hangi yol istenirse istensin ayni PAC dosyasini doner, hicbir sey loglamaz.

Kullanim: python3 pac-server.py <port> <proxy.pac>
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
PAC_PATH = sys.argv[2] if len(sys.argv) > 2 else "proxy.pac"


class PacHandler(BaseHTTPRequestHandler):
    server_version = "discord-dpi-bridge-pac/1.0"
    protocol_version = "HTTP/1.1"

    def _send(self, body: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ns-proxy-autoconfig")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        try:
            with open(PAC_PATH, "rb") as f:
                body = f.read()
        except OSError:
            self.send_error(404, "proxy.pac yok")
            return
        self._send(body)
        self.wfile.write(body)

    def do_HEAD(self) -> None:  # noqa: N802
        try:
            with open(PAC_PATH, "rb") as f:
                body = f.read()
        except OSError:
            self.send_error(404, "proxy.pac yok")
            return
        self._send(body)

    def log_message(self, fmt, *args):  # sessiz
        return


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), PacHandler).serve_forever()
