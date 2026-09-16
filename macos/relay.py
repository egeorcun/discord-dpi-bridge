#!/usr/bin/python3
"""
discord-dpi-bridge / macOS - guncelleyici koprusu (relay)

Discord'un guncelleyicisi (updater.node, Rust reqwest 0.11) macOS sistem proxy / PAC ayarini
OKUMAZ; dogrudan baglanir ve DPI tarafindan kesilir. Cozum Windows surumundekiyle ayni:
/etc/hosts guncelleyici alanlarini loopback'e cevirir, bu kopru 127.0.0.1:443 ve [::1]:443'u
dinler, TLS ClientHello'daki SNI'ye bakar ve baglantiyi ByeDPI'nin SOCKS5 proxy'si uzerinden
gercek sunucuya tasir. TLS'e dokunulmaz; sertifika dogrulamasi istemcide kalir.

- Yalnizca --hosts ile verilen alan adlari tasinir; baska SNI gelirse baglanti kapatilir.
- Alan adi hosts'ta loopback'e cevrildigi icin gercek IP DoH ile cozulur ve SOCKS5'e IP verilir
  (aksi halde proxy de loopback'e cozer ve kopruye geri doner).
- 443 root ister: LaunchDaemon olarak root baslar, portu acar, hemen 'nobody' kullanicisina duser.

Kullanim: relay.py --socks 127.0.0.1:1080 --doh https://1.1.1.1/dns-query --hosts a.com,b.com
"""
import argparse
import ipaddress
import json
import os
import pwd
import socket
import ssl
import sys
import threading
import time
import urllib.request

DOH_TTL = 300


class EmptyConnection(Exception):
    """Hic veri gondermeden kapanan baglanti (orn. status.sh'in port yoklamasi); loglanmaz."""
_cache = {}
_cache_lock = threading.Lock()


def log(msg):
    sys.stderr.write("[%s] %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    sys.stderr.flush()


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--socks", default="127.0.0.1:1080")
    p.add_argument("--doh", default="https://1.1.1.1/dns-query")
    p.add_argument("--hosts", required=True, help="virgulle ayrilmis alan adlari")
    p.add_argument("--port", type=int, default=443)
    p.add_argument("--user", default="nobody", help="port acildiktan sonra dusulecek kullanici")
    a = p.parse_args()
    host, _, port = a.socks.rpartition(":")
    a.socks = (host, int(port))
    a.hosts = {h.strip().lower() for h in a.hosts.split(",") if h.strip()}
    return a


def is_loopback(ip):
    try:
        return ipaddress.ip_address(ip).is_loopback
    except ValueError:
        return True


def resolve(host, doh_url):
    """Gercek IPv4'u DoH ile coz; loopback sonucu asla dondurme (dongu korumasi)."""
    now = time.time()
    with _cache_lock:
        hit = _cache.get(host)
        if hit and hit[1] > now:
            return hit[0]
    req = urllib.request.Request(
        "%s?name=%s&type=A" % (doh_url, host), headers={"accept": "application/dns-json"}
    )
    with urllib.request.urlopen(req, timeout=10, context=ssl.create_default_context()) as r:
        data = json.load(r)
    ips = [a["data"] for a in data.get("Answer", []) if a.get("type") == 1 and not is_loopback(a.get("data", ""))]
    if not ips:
        raise OSError("%s icin DoH A kaydi yok" % host)
    with _cache_lock:
        _cache[host] = (ips[0], now + DOH_TTL)
    return ips[0]


def read_client_hello(sock):
    """TLS kaydinin tamamini oku (SNI cikarmak icin). Ham baytlari dondurur."""
    buf = b""
    while len(buf) < 5:
        d = sock.recv(5 - len(buf))
        if not d:
            if not buf:
                raise EmptyConnection()
            raise OSError("erken kapandi")
        buf += d
    if buf[0] != 0x16:
        raise OSError("TLS degil")
    need = 5 + int.from_bytes(buf[3:5], "big")
    while len(buf) < need:
        d = sock.recv(need - len(buf))
        if not d:
            raise OSError("erken kapandi")
        buf += d
    return buf


def sni_of(rec):
    """TLS kaydindaki ClientHello'dan server_name uzantisini cikar; yoksa None."""
    try:
        p = 5
        if rec[p] != 0x01:  # handshake type: client_hello
            return None
        p += 4 + 2 + 32  # handshake header, version, random
        p += 1 + rec[p]  # session id
        p += 2 + int.from_bytes(rec[p:p + 2], "big")  # cipher suites
        p += 1 + rec[p]  # compression
        end = p + 2 + int.from_bytes(rec[p:p + 2], "big")
        p += 2
        while p + 4 <= end:
            etype = int.from_bytes(rec[p:p + 2], "big")
            elen = int.from_bytes(rec[p + 2:p + 4], "big")
            p += 4
            if etype == 0:  # server_name
                q = p + 2
                if rec[q] == 0:
                    n = int.from_bytes(rec[q + 1:q + 3], "big")
                    return rec[q + 3:q + 3 + n].decode("ascii").lower()
            p += elen
    except (IndexError, UnicodeDecodeError):
        pass
    return None


def recv_exact(s, n):
    buf = b""
    while len(buf) < n:
        d = s.recv(n - len(buf))
        if not d:
            raise OSError("SOCKS5 erken kapandi")
        buf += d
    return buf


def socks5_connect(socks, ip, port):
    s = socket.create_connection(socks, timeout=15)
    try:
        s.sendall(b"\x05\x01\x00")
        if recv_exact(s, 2) != b"\x05\x00":
            raise OSError("SOCKS5 el sikisma reddedildi")
        s.sendall(b"\x05\x01\x00\x01" + socket.inet_aton(ip) + port.to_bytes(2, "big"))
        rep = recv_exact(s, 4)
        if rep[1] != 0:
            raise OSError("SOCKS5 connect hata kodu %d" % rep[1])
        recv_exact(s, {1: 4, 4: 16}.get(rep[3], 0) or recv_exact(s, 1)[0])
        recv_exact(s, 2)
        s.settimeout(None)
        return s
    except Exception:
        s.close()
        raise


def pipe(src, dst):
    try:
        while True:
            d = src.recv(65536)
            if not d:
                break
            dst.sendall(d)
    except OSError:
        pass
    finally:
        for s, how in ((dst, socket.SHUT_WR), (src, socket.SHUT_RD)):
            try:
                s.shutdown(how)
            except OSError:
                pass


def handle(client, args):
    upstream = None
    try:
        client.settimeout(15)
        hello = read_client_hello(client)
        host = sni_of(hello)
        if host not in args.hosts:
            log("reddedildi: SNI=%r izinli degil" % host)
            return
        ip = resolve(host, args.doh)
        upstream = socks5_connect(args.socks, ip, 443)
        upstream.sendall(hello)
        client.settimeout(None)
        t = threading.Thread(target=pipe, args=(upstream, client), daemon=True)
        t.start()
        pipe(client, upstream)
        t.join()
    except EmptyConnection:
        pass
    except Exception as e:  # noqa: BLE001
        log("baglanti hatasi: %s" % e)
    finally:
        for s in (client, upstream):
            if s is not None:
                try:
                    s.close()
                except OSError:
                    pass


def serve(listener, args):
    while True:
        try:
            c, _ = listener.accept()
        except OSError as e:
            log("accept hatasi: %s" % e)
            time.sleep(0.5)
            continue
        threading.Thread(target=handle, args=(c, args), daemon=True).start()


def main():
    args = parse_args()
    listeners = []
    for fam, addr in ((socket.AF_INET, "127.0.0.1"), (socket.AF_INET6, "::1")):
        try:
            s = socket.socket(fam, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if fam == socket.AF_INET6:
                s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            s.bind((addr, args.port))
            s.listen(64)
            listeners.append(s)
        except OSError as e:
            log("%s:%d dinlenemedi: %s" % (addr, args.port, e))
    if not listeners:
        sys.exit(1)
    if os.getuid() == 0:
        pw = pwd.getpwnam(args.user)
        os.setgroups([])
        os.setgid(pw.pw_gid)
        os.setuid(pw.pw_uid)
    log("hazir: port %d, alanlar: %s, SOCKS5 %s:%d" % (args.port, ",".join(sorted(args.hosts)), *args.socks))
    for s in listeners[1:]:
        threading.Thread(target=serve, args=(s, args), daemon=True).start()
    serve(listeners[0], args)


if __name__ == "__main__":
    main()
