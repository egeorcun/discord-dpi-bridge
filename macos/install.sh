#!/bin/bash
# discord-dpi-bridge / macOS kurulumu
#
# Ne yapar (hepsi geri alinabilir, uninstall.sh ile):
#  1. Xcode Command Line Tools var mi bakar (derleyici + git + python3 buradan gelir)
#  2. ByeDPI'yi kaynaktan derler (resmi macOS ikilisi yok) -> ~/Library/Application Support/discord-dpi-bridge/byedpi/ciadpi
#  3. ByeDPI'yi kullanici seviyesinde LaunchAgent olarak calistirir (SOCKS5 127.0.0.1:1080, acilista otomatik)
#  4. Yalnizca Discord alanlarini bu proxy'ye yonlendiren bir PAC dosyasi uretir ve 127.0.0.1'den sunar
#  5. Sistem proxy ayarina (networksetup) bu PAC'i yazar  -> Discord da, guncelleyicisi de ByeDPI'den gecer
#  6. DNS'i Cloudflare yapar ve DNS over HTTPS profili (.mobileconfig) uretip acar (kullanici onaylar)
#  7. status.sh ile dogrular
#
# Windows surumundeki hosts/relay/kisayol/gozcu parcalari macOS'ta GEREKMEZ: macOS'ta hem Electron
# hem de Discord'un guncelleyicisi sistem proxy (PAC) ayarina uyar.
#
# Kullanim: bash macos/install.sh [secenekler]
#   -y, --yes           Sorulari sormadan evet say
#   --dry-run           Hicbir sey degistirme, ne yapacagini anlat
#   --skip-dns          DNS / DoH ayarlarina dokunma
#   --skip-proxy        Sistem proxy ayarina dokunma (sadece ByeDPI'yi kur)
#   --system-socks      PAC yerine sistem geneli SOCKS proxy ayarla (tum uygulamalar ByeDPI'den gecer;
#                       guncelleyici PAC'e uymuyorsa yedek yol)
#   --byedpi-tag vX.Y.Z Belirli bir ByeDPI surumu (bos = en yeni)
# shellcheck disable=SC2329  # fonksiyonlar act() uzerinden dolayli cagrilir
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

YES=0; DRY=0; SKIP_DNS=0; SKIP_PROXY=0; SYSTEM_SOCKS=0; BYEDPI_TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) YES=1 ;;
    --dry-run) DRY=1 ;;
    --skip-dns) SKIP_DNS=1 ;;
    --skip-proxy) SKIP_PROXY=1 ;;
    --system-socks) SYSTEM_SOCKS=1 ;;
    --byedpi-tag) shift; BYEDPI_TAG="${1:-}" ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "bilinmeyen secenek: $1"; exit 2 ;;
  esac
  shift
done

need_macos
refuse_root

act() {
  # act "aciklama" komut args...
  local desc="$1"; shift
  if [ "$DRY" -eq 1 ]; then info "(dry-run) $desc"; return 0; fi
  info "$desc"
  "$@"
}

printf '%sdiscord-dpi-bridge kurulum (macOS)%s\n' "$C_CYAN" "$C_OFF"
[ "$DRY" -eq 1 ] && warn "DRY-RUN: hicbir sey degistirilmeyecek"
info "Kaynak : $REPO_DIR"
info "Hedef  : $APP_DIR"

# ---------- 1) gereksinimler ----------
step "Gereksinimler"
macver="$(sw_vers -productVersion)"
major="${macver%%.*}"
if [ "$major" -lt 12 ]; then
  fail "macOS $macver bulundu; en az macOS 12 (Monterey) gerekir."
  exit 1
fi
ok "macOS $macver ($(uname -m))"
if have_clt; then
  ok "Xcode Command Line Tools var ($(xcode-select -p))"
else
  fail "Xcode Command Line Tools yok. ByeDPI'yi derlemek icin gerekli (tek seferlik, ~1 GB)."
  info "Simdi kurulum penceresi acilacak; 'Yukle'ye bas, bitince bu betigi TEKRAR calistir."
  [ "$DRY" -eq 1 ] || xcode-select --install 2>/dev/null || true
  exit 1
fi
load_cfg
info "SOCKS5      : $SOCKS_HOST:$SOCKS_PORT"
info "ByeDPI args : $BYEDPI_ARGS"
if [ "$SYSTEM_SOCKS" -eq 1 ]; then info "Proxy modu  : sistem geneli SOCKS"; else info "Proxy modu  : PAC (yalnizca Discord alanlari) -> $PAC_URL"; fi

if [ "$DRY" -eq 0 ]; then
  mkdir -p "$APP_DIR/byedpi" "$PAC_DIR" "$LOG_DIR" "$AGENTS_DIR"
fi

# ---------- 2) ByeDPI derle ----------
step "ByeDPI (kaynaktan derleme)"
have_ver=""
[ -f "$BYEDPI_VER" ] && have_ver="$(tr -d '[:space:]' < "$BYEDPI_VER")"
want_tag="$BYEDPI_TAG"
if [ -z "$want_tag" ]; then
  # 1) GitHub API (releases/latest); 2) olmazsa git etiketlerinden en yuksek surum
  want_tag="$(curl -fsSL -m 20 -H 'User-Agent: discord-dpi-bridge' https://api.github.com/repos/hufrea/byedpi/releases/latest 2>/dev/null \
    | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null || true)"
fi
if [ -z "$want_tag" ]; then
  want_tag="$(git ls-remote --tags --refs https://github.com/hufrea/byedpi 2>/dev/null | sed 's,.*/,,' \
    | /usr/bin/python3 -c 'import re,sys; t=[x.strip() for x in sys.stdin if re.match(r"^v\d+(\.\d+)*$", x.strip())]; print(max(t, key=lambda v: tuple(int(n) for n in v[1:].split("."))) if t else "")' 2>/dev/null || true)"
fi
if [ -z "$want_tag" ]; then
  if [ -x "$BYEDPI_BIN" ]; then
    warn "GitHub'a ulasilamadi; eldeki ByeDPI ($have_ver) kullaniliyor"
    want_tag="$have_ver"
  else
    fail "ByeDPI surumu ogrenilemedi (GitHub API). --byedpi-tag vX.Y.Z ile elle ver."
    exit 1
  fi
fi
if [ -x "$BYEDPI_BIN" ] && [ "$have_ver" = "$want_tag" ]; then
  ok "ByeDPI zaten derli ($have_ver)"
else
  info "ByeDPI $want_tag derlenecek"
  build_byedpi() {
    local src="$APP_DIR/byedpi/src"
    rm -rf "$src"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$want_tag" https://github.com/hufrea/byedpi "$src"
    if ! ( cd "$src" && make -s CC=cc ) > "$LOG_DIR/build.log" 2>&1; then
      fail "derleme basarisiz; ayrintilar: $LOG_DIR/build.log"
      tail -20 "$LOG_DIR/build.log"
      return 1
    fi
    cp "$src/ciadpi" "$BYEDPI_BIN"
    chmod 755 "$BYEDPI_BIN"
    codesign -s - -f "$BYEDPI_BIN" >/dev/null 2>&1 || true   # ad-hoc imza (Apple Silicon icin)
    printf '%s\n' "$want_tag" > "$BYEDPI_VER"
    rm -rf "$src"
  }
  act "git clone + make -> $BYEDPI_BIN" build_byedpi
  if [ "$DRY" -eq 0 ]; then
    if "$BYEDPI_BIN" --help >/dev/null 2>&1 || "$BYEDPI_BIN" -h >/dev/null 2>&1; then
      ok "ByeDPI $want_tag hazir"
    else
      fail "ciadpi derlendi ama calismiyor: $BYEDPI_BIN"
      exit 1
    fi
  fi
fi

# ---------- 3) PAC dosyasi ----------
step "PAC (proxy otomatik yapilandirma)"
write_pac() {
  {
    echo "// discord-dpi-bridge: yalnizca Discord alanlari ByeDPI'nin SOCKS5 proxy'sinden gecer, geri kalani DIRECT."
    echo "// install.sh tarafindan uretildi; elle duzenleme, config.json -> macos.proxy_domains'i degistirip install.sh'i tekrar calistir."
    echo "function FindProxyForURL(url, host) {"
    echo "  host = host.toLowerCase();"
    for d in $PROXY_DOMAINS; do
      echo "  if (host == \"$d\" || dnsDomainIs(host, \".$d\")) return \"SOCKS5 $SOCKS_HOST:$SOCKS_PORT; SOCKS $SOCKS_HOST:$SOCKS_PORT\";"
    done
    echo "  return \"DIRECT\";"
    echo "}"
  } > "$PAC_FILE"
  cp "$MACOS_DIR/pac-server.py" "$PAC_SERVER"
  chmod 644 "$PAC_FILE" "$PAC_SERVER"
}
act "yaz: $PAC_FILE ($(echo "$PROXY_DOMAINS" | wc -w | tr -d ' ') alan)" write_pac
ok "PAC hazir"

# ---------- 4) LaunchAgent'lar ----------
step "Acilista otomatik baslatma (LaunchAgent)"
write_agent_plist() {
  # write_agent_plist <plist> <label> <log-adi> <program> [args...]
  local plist="$1" label="$2" logname="$3"; shift 3
  /usr/bin/python3 - "$plist" "$label" "$LOG_DIR/$logname" "$APP_DIR" "$@" <<'PY'
import plistlib, sys
plist, label, log, wd, *prog = sys.argv[1:]
d = {
    "Label": label,
    "ProgramArguments": prog,
    "WorkingDirectory": wd,
    "RunAtLoad": True,
    "KeepAlive": True,
    "ProcessType": "Background",
    "StandardOutPath": log,
    "StandardErrorPath": log,
    "ThrottleInterval": 5,
}
with open(plist, "wb") as f:
    plistlib.dump(d, f)
PY
}
install_agents() {
  agent_bootout "$LABEL_BYEDPI"; agent_bootout "$LABEL_PAC"
  # shellcheck disable=SC2086
  write_agent_plist "$PLIST_BYEDPI" "$LABEL_BYEDPI" byedpi.log "$BYEDPI_BIN" -i "$SOCKS_HOST" -p "$SOCKS_PORT" $BYEDPI_ARGS
  write_agent_plist "$PLIST_PAC" "$LABEL_PAC" pac.log /usr/bin/python3 "$PAC_SERVER" "$PAC_PORT" "$PAC_FILE"
  agent_bootstrap "$PLIST_BYEDPI"
  agent_bootstrap "$PLIST_PAC"
  sleep 2
}
act "$LABEL_BYEDPI + $LABEL_PAC" install_agents
if [ "$DRY" -eq 0 ]; then
  if agent_loaded "$LABEL_BYEDPI"; then ok "ByeDPI calisiyor"; else fail "ByeDPI agent yuklenemedi; log: $LOG_DIR/byedpi.log"; fi
  if agent_loaded "$LABEL_PAC"; then ok "PAC sunucusu calisiyor"; else fail "PAC agent yuklenemedi; log: $LOG_DIR/pac.log"; fi
fi

# ---------- 5) sistem proxy + DNS (networksetup, yonetici parolasi ister) ----------
services="$(network_services)"
if [ -z "$services" ]; then
  warn "networksetup hic ag servisi listelemedi; proxy/DNS adimlari atlandi"
  SKIP_PROXY=1; SKIP_DNS=1
fi
if [ "$SKIP_PROXY" -eq 0 ] || [ "$SKIP_DNS" -eq 0 ]; then
  step "Ag ayarlari (Wi-Fi / Ethernet)"
  if [ "$DRY" -eq 0 ]; then
    info "networksetup icin yonetici parolasi gerekiyor (bir kez)."
    sudo -v
  fi
  backup_network() {
    [ -f "$NET_BACKUP" ] && return 0
    : > "$NET_BACKUP"
    echo "$services" | while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      dns="$(networksetup -getdnsservers "$svc" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
      case "$dns" in *"any DNS Servers"*|"") dns="empty" ;; esac
      # yedek yokken bizim degerlerimiz zaten yaziliysa (klasor silinip yeniden kurulmus) "eski ayar" diye kaydetme
      [ "$dns" = "$DNS_V4${DNS_V6:+ $DNS_V6}" ] && dns="empty"
      pac="$(networksetup -getautoproxyurl "$svc" 2>/dev/null | awk -F': ' '/^URL/{u=$2} /^Enabled/{e=$2} END{print u "\t" e}')"
      socks="$(networksetup -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': ' '/^Enabled/{e=$2} /^Server/{s=$2} /^Port/{p=$2} END{print s "\t" p "\t" e}')"
      printf '%s\t%s\t%s\t%s\n' "$svc" "$dns" "$pac" "$socks" >> "$NET_BACKUP"
    done
  }
  act "eski ayarlari yedekle -> $NET_BACKUP" backup_network
fi

if [ "$SKIP_PROXY" -eq 1 ]; then
  warn "skip-proxy: sistem proxy ayarina dokunulmadi"
else
  echo "$services" | while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    if [ "$SYSTEM_SOCKS" -eq 1 ]; then
      act "'$svc': PAC kapat, SOCKS = $SOCKS_HOST:$SOCKS_PORT" bash -c \
        "sudo networksetup -setautoproxystate \"\$1\" off; sudo networksetup -setsocksfirewallproxy \"\$1\" \"\$2\" \"\$3\" off; sudo networksetup -setsocksfirewallproxystate \"\$1\" on" _ "$svc" "$SOCKS_HOST" "$SOCKS_PORT"
    else
      act "'$svc': SOCKS kapat, PAC = $PAC_URL" bash -c \
        "sudo networksetup -setsocksfirewallproxystate \"\$1\" off; sudo networksetup -setautoproxyurl \"\$1\" \"\$2\"; sudo networksetup -setautoproxystate \"\$1\" on" _ "$svc" "$PAC_URL"
    fi
  done
  ok "Sistem proxy ayarlandi"
fi

# ---------- 6) DNS + DoH profili ----------
if [ "$SKIP_DNS" -eq 1 ]; then
  warn "skip-dns: DNS ayarlarina dokunulmadi"
else
  step "DNS over HTTPS"
  echo "$services" | while IFS= read -r svc; do
    [ -n "$svc" ] || continue
    # shellcheck disable=SC2086
    act "'$svc': DNS = $DNS_V4 $DNS_V6" bash -c 'sudo networksetup -setdnsservers "$@"' _ "$svc" $DNS_V4 $DNS_V6
  done
  write_doh_profile() {
    # shellcheck disable=SC2086  # DNS listeleri bilerek kelimelere ayrilir
    /usr/bin/python3 - "$DOH_PROFILE" "$DOH_PROFILE_ID" "$DNS_TEMPLATE" $DNS_V4 $DNS_V6 <<'PY'
import plistlib, sys, uuid
path, ident, url, *servers = sys.argv[1:]
payload = {
    "PayloadType": "com.apple.dnsSettings.managed",
    "PayloadIdentifier": ident + ".payload",
    "PayloadUUID": str(uuid.uuid4()).upper(),
    "PayloadVersion": 1,
    "PayloadDisplayName": "DNS over HTTPS (Cloudflare)",
    "DNSSettings": {"DNSProtocol": "HTTPS", "ServerURL": url, "ServerAddresses": servers},
    "ProhibitDisablement": False,
}
profile = {
    "PayloadType": "Configuration",
    "PayloadIdentifier": ident,
    "PayloadUUID": str(uuid.uuid4()).upper(),
    "PayloadVersion": 1,
    "PayloadScope": "User",
    "PayloadDisplayName": "discord-dpi-bridge: DNS over HTTPS",
    "PayloadDescription": "Sistem DNS sorgularini sifreli (DoH) olarak Cloudflare'a gonderir; operatorun DNS engelini atlar. uninstall.sh ile kaldirilir.",
    "PayloadOrganization": "discord-dpi-bridge",
    "PayloadRemovalDisallowed": False,
    "PayloadContent": [payload],
}
with open(path, "wb") as f:
    plistlib.dump(profile, f)
PY
  }
  act "DoH profili uret -> $DOH_PROFILE" write_doh_profile
  if [ "$DRY" -eq 0 ]; then
    if profiles list 2>/dev/null | grep -q "$DOH_PROFILE_ID"; then
      ok "DoH profili zaten yuklu"
    else
      open "$DOH_PROFILE" || true
      echo
      warn "macOS profilleri komutla yuklemeye izin vermez; son adim sende:"
      info "  Sistem Ayarlari -> Genel -> Aygit Yonetimi (veya Gizlilik ve Guvenlik -> Profiller)"
      info "  'discord-dpi-bridge: DNS over HTTPS' -> Yukle... -> parola."
      info "  (Profil simdi indirildi; pencere acilmadiysa Sistem Ayarlari'ni ac, orada bekliyor.)"
      if [ "$YES" -eq 0 ]; then
        printf '   Profili yukledikten sonra Enter'"'"'a bas (atlamak icin de Enter): '; read -r _
      fi
      if profiles list 2>/dev/null | grep -q "$DOH_PROFILE_ID"; then ok "DoH profili yuklendi"
      else warn "DoH profili henuz yuklu degil. DNS engeli olan operatorlerde Discord acilmayabilir; profili sonra da yukleyebilirsin: open \"$DOH_PROFILE\""; fi
    fi
  fi
fi

# ---------- 7) dogrula ----------
if [ "$DRY" -eq 1 ]; then
  printf '\n%sDry-run bitti; degisiklik yapilmadi.%s\n' "$C_YEL" "$C_OFF"
  exit 0
fi
step "Dogrulama"
rc=0
bash "$MACOS_DIR/status.sh" || rc=$?
echo
info "Discord acikti ise TAMAMEN kapat (Cmd+Q, menu cubugundaki simgeden de Cikis) ve tekrar ac."
info "Discord'a hicbir bayrak/kisayol gerekmez; sistem proxy ayarini kendisi kullanir."
exit $rc
