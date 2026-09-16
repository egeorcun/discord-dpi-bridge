#!/bin/bash
# discord-dpi-bridge / macOS - ortak yardimcilar (install.sh, uninstall.sh, status.sh kaynak alir)
# macOS'un yerlesik bash 3.2'si ile uyumlu tutulur: dizi-sozluk, mapfile, ${var,,} YOK.
# shellcheck disable=SC2034  # degiskenler bu dosyayi kaynak alan betiklerde kullanilir

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$MACOS_DIR/.." && pwd)"
CONFIG="$REPO_DIR/config.json"

APP_DIR="$HOME/Library/Application Support/discord-dpi-bridge"
BYEDPI_BIN="$APP_DIR/byedpi/ciadpi"
BYEDPI_VER="$APP_DIR/byedpi/version.txt"
PAC_DIR="$APP_DIR/pac"
PAC_FILE="$PAC_DIR/proxy.pac"
PAC_SERVER="$APP_DIR/pac-server.py"
LOG_DIR="$APP_DIR/logs"
NET_BACKUP="$APP_DIR/network-backup.txt"
DOH_PROFILE="$APP_DIR/discord-dpi-bridge-doh.mobileconfig"
AGENTS_DIR="$HOME/Library/LaunchAgents"
# Guncelleyici koprusu root olarak calisir; betigi kullanicinin yazabilecegi bir yerden CALISTIRMA (yetki yukseltme).
RELAY_SYS_DIR="/Library/Application Support/discord-dpi-bridge"
RELAY_SCRIPT="$RELAY_SYS_DIR/relay.py"
HOSTS_FILE="/etc/hosts"
HOSTS_BEGIN="# >>> discord-dpi-bridge (uninstall.sh kaldirir)"
HOSTS_END="# <<< discord-dpi-bridge"

# ---- renkli cikti ----
if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_OFF=$'\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YEL=''; C_RED=''; C_GRAY=''; C_OFF=''
fi
step() { printf '\n%s== %s%s\n' "$C_CYAN" "$*" "$C_OFF"; }
ok()   { printf '   %s[OK]%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   %s[!]%s %s\n' "$C_YEL" "$C_OFF" "$*"; }
fail() { printf '   %s[HATA]%s %s\n' "$C_RED" "$C_OFF" "$*"; }

need_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    fail "Bu betik yalnizca macOS icindir. Windows icin install.ps1 kullan."
    exit 1
  fi
}

refuse_root() {
  if [ "$(id -u)" -eq 0 ]; then
    fail "sudo ile CALISTIRMA. Betik kullanici olarak calisir; gerekli yerde parolani kendisi ister."
    info "Dogru kullanim:  bash macos/$(basename "$0")"
    exit 1
  fi
}

# Xcode Command Line Tools: derleyici + git + python3 buradan gelir.
# DoH profili sistem (aygit) kapsaminda yuklenir; `profiles list` sudo'suz yalnizca kullanici profillerini gosterir,
# system_profiler ise sudo'suz aygit profillerini de listeler.
doh_profile_installed() { system_profiler SPConfigurationProfileDataType 2>/dev/null | grep -q "Identifier: $DOH_PROFILE_ID$"; }
have_clt() { xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ] && /usr/bin/python3 -c 'import sys' >/dev/null 2>&1; }

# ---- config.json okuma (python3 ile; noktali anahtar: cfg socks.port) ----
# Liste degerleri bosluk ile ayrilarak tek satirda doner; yoksa bos doner.
cfg() {
  /usr/bin/python3 - "$CONFIG" "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    for k in sys.argv[2].split("."):
        d = d[k]
except Exception:
    sys.exit(0)
if isinstance(d, list):
    print(" ".join(str(x) for x in d))
elif isinstance(d, bool):
    print("true" if d else "false")
elif d is None:
    pass
else:
    print(d)
PY
}

load_cfg() {
  SOCKS_HOST="$(cfg socks.host)";        [ -n "$SOCKS_HOST" ] || SOCKS_HOST=127.0.0.1
  SOCKS_PORT="$(cfg socks.port)";        [ -n "$SOCKS_PORT" ] || SOCKS_PORT=1080
  BYEDPI_ARGS="$(cfg macos.byedpi_args)"
  [ -n "$BYEDPI_ARGS" ] || BYEDPI_ARGS="$(cfg byedpi.args)"
  DNS_V4="$(cfg dns.v4)";                [ -n "$DNS_V4" ] || DNS_V4="1.1.1.1 1.0.0.1"
  DNS_V6="$(cfg dns.v6)"
  DNS_TEMPLATE="$(cfg dns.template)";    [ -n "$DNS_TEMPLATE" ] || DNS_TEMPLATE="https://cloudflare-dns.com/dns-query"
  DOH_URL="$(cfg doh.url)";              [ -n "$DOH_URL" ] || DOH_URL="https://1.1.1.1/dns-query"
  PAC_PORT="$(cfg macos.pac_port)";      [ -n "$PAC_PORT" ] || PAC_PORT=18080
  PROXY_DOMAINS="$(cfg macos.proxy_domains)"
  [ -n "$PROXY_DOMAINS" ] || PROXY_DOMAINS="discord.com discordapp.com discordapp.net discord.gg discordcdn.com discord.media discordstatus.com"
  LABEL_PREFIX="$(cfg macos.launchd_prefix)"; [ -n "$LABEL_PREFIX" ] || LABEL_PREFIX="com.egeorcun.discord-dpi-bridge"
  LABEL_BYEDPI="$LABEL_PREFIX.byedpi"
  LABEL_PAC="$LABEL_PREFIX.pac"
  PLIST_BYEDPI="$AGENTS_DIR/$LABEL_BYEDPI.plist"
  PLIST_PAC="$AGENTS_DIR/$LABEL_PAC.plist"
  LABEL_RELAY="$LABEL_PREFIX.relay"
  PLIST_RELAY="/Library/LaunchDaemons/$LABEL_RELAY.plist"
  RELAY_HOSTS="$(cfg macos.relay_hosts)"
  [ -n "$RELAY_HOSTS" ] || RELAY_HOSTS="updates.discord.com stable.dl2.discordapp.net dl.discordapp.net"
  DOH_PROFILE_ID="$LABEL_PREFIX.doh"
  PAC_URL="http://127.0.0.1:$PAC_PORT/proxy.pac"
}

# ---- ag servisleri (Wi-Fi, Ethernet, ...) ----
# Devre disi olanlar (basinda * olanlar) atlanir. Her satir bir servis adi.
network_services() {
  networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | grep -v '^\*' || true
}

# Su an internete cikan servis (varsayilan rota hangi arayuzdeyse)
primary_service() {
  local ifc
  ifc="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  [ -n "$ifc" ] || return 0
  networksetup -listnetworkserviceorder 2>/dev/null \
    | awk -v ifc="$ifc" '
        /^\([0-9]+\) /   { name=$0; sub(/^\([0-9]+\) /, "", name) }
        /Device: /       { dev=$0; sub(/.*Device: /, "", dev); sub(/\)$/, "", dev); if (dev==ifc) { print name; exit } }'
}

# ---- launchd ----
agent_loaded() { launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1; }
# bootout asenkron: servis tamamen kalkmadan bootstrap edilirse "5: Input/output error" verir. Kalkmasini bekle.
agent_bootout() {
  launchctl bootout "gui/$(id -u)/$1" >/dev/null 2>&1 || true
  local i=0
  while agent_loaded "$1" && [ $i -lt 20 ]; do sleep 0.5; i=$((i+1)); done
}
agent_bootstrap() {
  # $1 = plist yolu; gecici hatalara karsi birkac kez dene
  local i
  for i in 1 2 3 4 5; do
    launchctl bootstrap "gui/$(id -u)" "$1" 2>/dev/null && return 0
    sleep 1
  done
  launchctl load -w "$1" 2>/dev/null
}

# ---- hosts blogu (guncelleyici alanlari -> loopback -> relay) ----
hosts_without_block() { sed "/^$HOSTS_BEGIN\$/,/^$HOSTS_END\$/d" "$HOSTS_FILE"; }
hosts_has_block() { grep -qxF "$HOSTS_BEGIN" "$HOSTS_FILE" 2>/dev/null; }
relay_running() { pgrep -f "$RELAY_SCRIPT" >/dev/null 2>&1 && nc -z 127.0.0.1 443 >/dev/null 2>&1; }
flush_dns() { dscacheutil -flushcache 2>/dev/null || true; sudo killall -HUP mDNSResponder 2>/dev/null || true; }
