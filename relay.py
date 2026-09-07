#!/usr/bin/env python3
"""discord-dpi-bridge relay

Proxy desteklemeyen istemciler (ornegin Discord'un Rust guncelleyicisi) icin
yerel TCP -> SOCKS5 koprusu. Hosts dosyasi hedef alan adini bir loopback
IP'ye yonlendirir; bu program o IP'yi dinler ve baglantiyi ByeDPI'nin SOCKS5
proxy'si uzerinden gercek sunucuya tasir. TLS'e dokunulmaz: sertifika
dogrulamasi istemcide oldugu gibi kalir.

Kritik ayrinti: hedef alan adi hosts'ta loopback'e cevrildigi icin SOCKS5'e
alan adi VERILEMEZ (proxy de ayni DNS'i kullanir ve kendine geri baglanir).
Gercek IP DoH ile cozulur ve SOCKS5'e IP olarak verilir. SNI TLS ClientHello
icinde tasindigindan ByeDPI'nin DPI atlatmasi bundan etkilenmez.

Kullanim:  python relay.py [config.json]
"""
import ipaddress
import json
import os
import socket
import ssl
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "config.json")
LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(CFG_PATH)), "relay.log")
LOG_MAX = 5 * 1024 * 1024

_log_lock = threading.Lock()
_cache = {}
_cache_lock = threading.Lock()


def log(msg):
    line = "[%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    with _log_lock:
        try:
            if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > LOG_MAX:
                os.replace(LOG_PATH, LOG_PATH + ".old")
            with open(LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError:
            pass
    try:
        sys.stdout.write(line)
        sys.stdout.flush()
    except (OSError, ValueError):
        pass


def load_config():
    with open(CFG_PATH, encoding="utf-8") as f:
        cfg = json.load(f)
    socks = cfg.get("socks", {})
    doh = cfg.get("doh", {})
    return {
        "socks": (socks.get("host", "127.0.0.1"), int(socks.get("port", 1080))),
        "doh_url": doh.get("url", "https://1.1.1.1/dns-query"),
        "doh_ttl": int(doh.get("ttl", 300)),
        "routes": cfg.get("routes", []),
    }


CFG = load_config()


def _is_loopback(ip):
    try:
        return ipaddress.ip_address(ip).is_loopback
    except ValueError:
        return False


def resolve(host):
    """Gercek IPv4'u DoH ile coz (hosts dosyasini atlar). Basarisizsa sistem
    cozumleyicisine dus ama loopback sonucu reddet (dongu korumasi)."""
    with _cache_lock:
        hit = _cache.get(host)
        if hit and hit[1] > time.time():
            return hit[0]
    ip = None
    try:
        req = urllib.request.Request(
            "%s?name=%s&type=A" % (CFG["doh_url"], host),
            headers={"accept": "application/dns-json"},
        )
        with urllib.request.urlopen(req, timeout=10, context=ssl.create_default_context()) as r:
            data = json.load(r)
        for a in data.get("Answer", []):
            if a.get("type") == 1 and not _is_loopback(a.get("data", "")):
                ip = a["data"]
                break
        if ip:
            log("DoH: %s -> %s" % (host, ip))
    except Exception as e:  # noqa: BLE001
        log("DoH basarisiz (%s): %s; sistem cozumleyicisi deneniyor" % (host, e))
    if not ip:
        for _fam, _t, _p, _c, sa in socket.getaddrinfo(host, None, socket.AF_INET):
            if not _is_loopback(sa[0]):
                ip = sa[0]
                break
    if not ip:
        raise OSError("%s icin loopback disinda A kaydi bulunamadi" % host)
    with _cache_lock:
        _cache[host] = (ip, time.time() + CFG["doh_ttl"])
    return ip


def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        d = s.recv(n - len(buf))
        if not d:
            raise OSError("baglanti erken kapandi")
        buf += d
    return buf


def socks5_connect(ip, port):
    s = socket.create_connection(CFG["socks"], timeout=15)
    try:
        s.sendall(b"\x05\x01\x00")
        if recv_exact(s, 2) != b"\x05\x00":
            raise OSError("SOCKS5 el sikisma reddedildi")
        s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton(ip) + port.to_bytes(2, "big"))
        rep = recv_exact(s, 4)
        if rep[1] != 0:
            raise OSError("SOCKS5 connect hata kodu %d" % rep[1])
        atyp = rep[3]
        if atyp == 1:
            recv_exact(s, 4)
        elif atyp == 4:
            recv_exact(s, 16)
        else:
            recv_exact(s, recv_exact(s, 1)[0])
        recv_exact(s, 2)
        s.settimeout(None)
        return s
    except Exception:
        s.close()
        raise


def pipe(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except OSError:
        pass
    finally:
        for x in (a, b):
            try:
                x.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                x.close()
            except OSError:
                pass


def handle(client, host, port):
    try:
        up = socks5_connect(resolve(host), port)
    except Exception as e:  # noqa: BLE001
        log("[HATA] %s:%d -> %s" % (host, port, e))
        client.close()
        return
    threading.Thread(target=pipe, args=(client, up), daemon=True).start()
    threading.Thread(target=pipe, args=(up, client), daemon=True).start()


def listen(lip, lport, host, port, ok):
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((lip, lport))
    except OSError as e:
        log("[HATA] %s:%d dinlenemiyor: %s" % (lip, lport, e))
        return
    srv.listen(128)
    ok.append(1)
    log("[OK] %s:%d -> %s:%d (SOCKS5 %s:%d)" % (lip, lport, host, port, CFG["socks"][0], CFG["socks"][1]))
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c, host, port), daemon=True).start()


def main():
    if not CFG["routes"]:
        log("[HATA] config.json icinde 'routes' bos")
        return 2
    ok = []
    for r in CFG["routes"]:
        host, port = r["host"], int(r.get("port", 443))
        lip, lport = r["listen"], int(r.get("listen_port", port))
        threading.Thread(target=listen, args=(lip, lport, host, port, ok), daemon=True).start()
    time.sleep(1.0)
    if not ok:
        log("[HATA] hicbir dinleyici ayaga kalkmadi; cikiliyor")
        return 1
    threading.Event().wait()
    return 0


if __name__ == "__main__":
    sys.exit(main())
