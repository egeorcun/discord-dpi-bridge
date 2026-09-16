#!/bin/bash
# discord-dpi-bridge / macOS - saglik kontrolu. Yonetici GEREKMEZ.
# Her bileseni tek tek test eder; cikis kodu 0 = her sey yolunda, 1 = sorun var.
# Kullanim: bash macos/status.sh [--no-network]
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
need_macos
NO_NET=0
[ "${1:-}" = "--no-network" ] && NO_NET=1
if ! have_clt; then fail "Xcode Command Line Tools yok; once install.sh"; exit 1; fi
load_cfg

problems=0
row() {
  # row ok|bad|info "ad" "detay"
  local mark color
  case "$1" in
    ok)   mark='[OK]  '; color="$C_GREEN" ;;
    info) mark='[--]  '; color="$C_GRAY" ;;
    *)    mark='[HATA]'; color="$C_RED"; problems=$((problems + 1)) ;;
  esac
  printf '  %s%s %-38s %s%s\n' "$color" "$mark" "$2" "$3" "$C_OFF"
}
head1() { printf '\n%s%s%s\n' "$C_YEL" "$*" "$C_OFF"; }

printf '\n%sdiscord-dpi-bridge durum (macOS)%s\n' "$C_CYAN" "$C_OFF"

# --- 1) ByeDPI
head1 "ByeDPI (SOCKS5 proxy)"
if [ -x "$BYEDPI_BIN" ]; then row ok "ciadpi ikilisi" "$(cat "$BYEDPI_VER" 2>/dev/null || echo '?') ($(file -b "$BYEDPI_BIN" | cut -d, -f1))"
else row bad "ciadpi ikilisi" "yok -> install.sh"; fi
if agent_loaded "$LABEL_BYEDPI"; then row ok "LaunchAgent $LABEL_BYEDPI" "yuklu"; else row bad "LaunchAgent $LABEL_BYEDPI" "yuklu degil"; fi
pids="$(pgrep -f "$BYEDPI_BIN" 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
if [ -n "$pids" ]; then row ok "ciadpi sureci" "PID $pids"; else row bad "ciadpi sureci" "calismiyor (log: $LOG_DIR/byedpi.log)"; fi
if lsof -nP -iTCP:"$SOCKS_PORT" -sTCP:LISTEN 2>/dev/null | grep -q ciadpi; then row ok "port $SOCKS_PORT dinleniyor" "$SOCKS_HOST"
else row bad "port $SOCKS_PORT dinleniyor" "hayir"; fi

# --- 2) PAC
head1 "PAC (yalnizca Discord alanlari proxy'ye)"
if [ -f "$PAC_FILE" ]; then row ok "proxy.pac" "$(grep -c 'dnsDomainIs' "$PAC_FILE") alan"; else row bad "proxy.pac" "yok"; fi
if agent_loaded "$LABEL_PAC"; then row ok "LaunchAgent $LABEL_PAC" "yuklu"; else row bad "LaunchAgent $LABEL_PAC" "yuklu degil"; fi
if curl -fsS -m 3 --noproxy '*' "$PAC_URL" 2>/dev/null | grep -q FindProxyForURL; then row ok "PAC sunucusu" "$PAC_URL"; else row bad "PAC sunucusu" "$PAC_URL cevap vermiyor"; fi

# --- 2b) Guncelleyici koprusu
head1 "Guncelleyici koprusu (Discord updater PAC'e uymaz)"
if [ -f "$PLIST_RELAY" ]; then row ok "LaunchDaemon $LABEL_RELAY" "kurulu"; else row bad "LaunchDaemon $LABEL_RELAY" "yok -> install.sh"; fi
if relay_running; then row ok "relay" "127.0.0.1:443 dinleniyor"; else row bad "relay" "calismiyor (log: $LOG_DIR/relay.log)"; fi
if hosts_has_block; then
  miss=""; for h in $RELAY_HOSTS; do grep -qE "^127\.0\.0\.1[[:space:]]+$h\$" "$HOSTS_FILE" || miss="$miss $h"; done
  if [ -z "$miss" ]; then row ok "/etc/hosts" "$(echo $RELAY_HOSTS | wc -w | tr -d ' ') alan -> 127.0.0.1"; else row bad "/etc/hosts" "eksik:$miss -> install.sh"; fi
else row bad "/etc/hosts" "girdi yok -> install.sh"; fi

# --- 3) Sistem proxy
head1 "Sistem proxy ayari"
prim="$(primary_service)"
services="$(network_services)"
if [ -z "$prim" ]; then row info "aktif ag servisi" "bulunamadi (internet yok?)"; fi
while IFS= read -r svc; do
  [ -n "$svc" ] || continue
  tag="$svc"; [ "$svc" = "$prim" ] && tag="$svc (aktif)"
  pacurl="$(networksetup -getautoproxyurl "$svc" 2>/dev/null | awk -F': ' '/^URL/{print $2}')"
  pacen="$(networksetup -getautoproxyurl "$svc" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')"
  socksen="$(networksetup -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')"
  sockssrv="$(networksetup -getsocksfirewallproxy "$svc" 2>/dev/null | awk -F': ' '/^Server/{print $2}')"
  if [ "$pacen" = "Yes" ] && [ "$pacurl" = "$PAC_URL" ]; then row ok "'$tag'" "PAC etkin"
  elif [ "$socksen" = "Yes" ] && [ "$sockssrv" = "$SOCKS_HOST" ]; then row ok "'$tag'" "sistem SOCKS etkin (system-socks modu)"
  elif [ "$svc" = "$prim" ]; then row bad "'$tag'" "proxy ayari YOK -> install.sh"
  else row info "'$tag'" "proxy ayari yok (aktif servis degil)"; fi
done <<< "$services"

# --- 4) DNS
head1 "DNS"
if [ -n "$prim" ]; then
  dns="$(networksetup -getdnsservers "$prim" 2>/dev/null | tr '\n' ' ')"
  hit=0; for s in $DNS_V4; do case " $dns " in *" $s "*) hit=1 ;; esac; done
  if [ "$hit" -eq 1 ]; then row ok "'$prim' DNS sunuculari" "$dns"; else row bad "'$prim' DNS sunuculari" "${dns:-otomatik} -> install.sh"; fi
fi
if doh_profile_installed; then row ok "DoH profili" "yuklu"
else row bad "DoH profili" "yuklu degil -> open \"$DOH_PROFILE\" ve Sistem Ayarlari'ndan yukle"; fi

# --- 5) Ag testleri
if [ "$NO_NET" -eq 0 ]; then
  head1 "Ag testleri"
  t1="$(curl -s -m 15 -o /dev/null -w '%{http_code}' --socks5-hostname "$SOCKS_HOST:$SOCKS_PORT" 'https://discord.com/api/v9/gateway' 2>/dev/null || true)"
  if [ "$t1" = "200" ]; then row ok "discord.com (SOCKS5 uzerinden)" "HTTP $t1"; else row bad "discord.com (SOCKS5 uzerinden)" "HTTP $t1 -> ByeDPI parametreleri (config.json byedpi.args) operatorune uymuyor olabilir"; fi
  # guncelleyicinin yaptigi gibi: proxy'siz, sistem cozumleyicisi (hosts -> relay) ile
  t2="$(curl --noproxy '*' -s -m 15 -o /dev/null -w '%{http_code}' 'https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=osx&arch=arm64' 2>/dev/null || true)"
  case "$t2" in 2*|3*) row ok "guncelleme sunucusu (relay uzerinden)" "HTTP $t2" ;; *) row bad "guncelleme sunucusu (relay uzerinden)" "HTTP $t2 -> Discord 'Update failed' der" ;; esac
  t3="$(curl --noproxy '*' -s -m 10 -o /dev/null -w '%{http_code}' 'https://discord.com/' 2>/dev/null || true)"
  if [ "$t3" = "200" ]; then row info "discord.com (dogrudan, bilgi)" "HTTP 200 (ECH/DoH sayesinde olabilir)"; else row info "discord.com (dogrudan, bilgi)" "HTTP $t3 (engelli - beklenen)"; fi
  # DNS zehirlenmesi: sistem cozumleyicisi (DoH profili dahil) vs. dogrudan DoH sorgusu
  sys_ips="$(dscacheutil -q host -a name discord.com 2>/dev/null | awk '/^ip_address/{print $2}' | sort -u)"
  real_ips="$(curl -fsS -m 10 -H 'accept: application/dns-json' "$DOH_URL?name=discord.com&type=A" 2>/dev/null \
    | /usr/bin/python3 -c 'import json,sys; [print(a["data"]) for a in json.load(sys.stdin).get("Answer",[]) if a.get("type")==1]' 2>/dev/null | sort -u)"
  if [ -z "$sys_ips" ] || [ -z "$real_ips" ]; then row info "DNS karsilastirma" "yapilamadi"
  else
    poison=""; real_flat="${real_ips//$'\n'/ }"
    for ip in $sys_ips; do case " $real_flat " in *" $ip "*) ;; *) poison="$poison $ip" ;; esac; done
    if [ -z "$poison" ]; then row ok "DNS zehirlenmesi" "yok (sistem = DoH)"; else row bad "DNS zehirlenmesi" "sistem$poison donuyor, gercek: $real_flat"; fi
  fi
fi

echo
if [ "$problems" -eq 0 ]; then printf '%sHer sey yolunda.%s\n' "$C_GREEN" "$C_OFF"; exit 0; fi
printf '%s%d sorun bulundu.%s\n' "$C_RED" "$problems" "$C_OFF"
exit 1
