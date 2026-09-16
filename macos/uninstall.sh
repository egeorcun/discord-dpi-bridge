#!/bin/bash
# discord-dpi-bridge / macOS - kaldirma. install.sh'in yaptigi her seyi geri alir:
#  - ByeDPI ve PAC LaunchAgent'larini durdurur ve siler
#  - Sistem proxy ayarini (PAC / SOCKS) yedekten geri yukler
#  - DNS sunucularini yedekten geri yukler, DoH profilini kaldirir (--keep-dns ile korunur)
#  - Kurulum klasorunu siler (sorar)
#
# Kullanim: bash macos/uninstall.sh [-y] [--keep-dns]
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

YES=0; KEEP_DNS=0
while [ $# -gt 0 ]; do
  case "$1" in
    -y|--yes) YES=1 ;;
    --keep-dns) KEEP_DNS=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) fail "bilinmeyen secenek: $1"; exit 2 ;;
  esac
  shift
done
need_macos
refuse_root
load_cfg

ask() {
  [ "$YES" -eq 1 ] && return 0
  local a
  printf '   %s [e/H] ' "$1"; read -r a
  case "$a" in e|E|evet|Evet|y|Y|yes) return 0 ;; *) return 1 ;; esac
}

printf '%sdiscord-dpi-bridge kaldirma (macOS)%s\n' "$C_CYAN" "$C_OFF"

step "LaunchAgent'lar"
agent_bootout "$LABEL_BYEDPI"; agent_bootout "$LABEL_PAC"
rm -f "$PLIST_BYEDPI" "$PLIST_PAC"
pkill -f "$BYEDPI_BIN" 2>/dev/null || true
pkill -f "$PAC_SERVER" 2>/dev/null || true
ok "ByeDPI ve PAC sunucusu durduruldu, acilis girdileri silindi"

services="$(network_services)"
if [ -n "$services" ]; then
  step "Ag ayarlari"
  info "networksetup icin yonetici parolasi gerekiyor (bir kez)."
  sudo -v
  restore_from_backup() {
    # yedek satiri: svc \t dns \t pacurl \t pacenabled \t sockshost \t socksport \t socksenabled
    local svc="$1" dns="$2" pacurl="$3" pacen="$4" shost="$5" sport="$6" sen="$7"
    if [ "$KEEP_DNS" -eq 1 ]; then
      info "'$svc' DNS: korunuyor (keep-dns)"
    elif [ "$dns" = "empty" ] || [ -z "$dns" ]; then
      sudo networksetup -setdnsservers "$svc" empty
      info "'$svc' DNS: otomatik (DHCP)"
    else
      # shellcheck disable=SC2086
      sudo networksetup -setdnsservers "$svc" $dns
      info "'$svc' DNS: $dns"
    fi
    if [ -n "$pacurl" ] && [ "$pacurl" != "(null)" ] && [ "$pacurl" != "$PAC_URL" ]; then
      sudo networksetup -setautoproxyurl "$svc" "$pacurl"
      [ "$pacen" = "Yes" ] || sudo networksetup -setautoproxystate "$svc" off
      info "'$svc' PAC: $pacurl (etkin: $pacen)"
    else
      sudo networksetup -setautoproxystate "$svc" off
      info "'$svc' PAC: kapali"
    fi
    if [ -n "$shost" ] && [ "$shost" != "$SOCKS_HOST" ] && [ "$sen" = "Yes" ]; then
      sudo networksetup -setsocksfirewallproxy "$svc" "$shost" "$sport" off
      info "'$svc' SOCKS: $shost:$sport"
    else
      sudo networksetup -setsocksfirewallproxystate "$svc" off
      info "'$svc' SOCKS: kapali"
    fi
  }
  if [ -f "$NET_BACKUP" ]; then
    while IFS=$'\t' read -r svc dns pacurl pacen shost sport sen; do
      [ -n "$svc" ] || continue
      restore_from_backup "$svc" "$dns" "$pacurl" "$pacen" "$shost" "$sport" "$sen"
    done < "$NET_BACKUP"
    ok "Yedekten geri yuklendi ($NET_BACKUP)"
  else
    warn "Yedek dosyasi yok; proxy kapatiliyor, DNS otomatige aliniyor"
    echo "$services" | while IFS= read -r svc; do
      [ -n "$svc" ] || continue
      sudo networksetup -setautoproxystate "$svc" off
      sudo networksetup -setsocksfirewallproxystate "$svc" off
      [ "$KEEP_DNS" -eq 1 ] || sudo networksetup -setdnsservers "$svc" empty
    done
    ok "Proxy kapatildi"
  fi
fi

step "DNS over HTTPS profili"
if [ "$KEEP_DNS" -eq 1 ]; then
  info "keep-dns: profil korunuyor"
elif profiles list 2>/dev/null | grep -q "$DOH_PROFILE_ID"; then
  if profiles remove -identifier "$DOH_PROFILE_ID" >/dev/null 2>&1; then
    ok "profil kaldirildi"
  else
    warn "Profil komutla kaldirilamadi. Elle: Sistem Ayarlari -> Genel -> Aygit Yonetimi -> 'discord-dpi-bridge: DNS over HTTPS' -> Sil"
  fi
else
  info "yuklu profil yok"
fi
dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

step "Kurulum klasoru"
if [ -d "$APP_DIR" ]; then
  if ask "\"$APP_DIR\" silinsin mi? (ByeDPI, PAC, loglar, yedek)"; then
    rm -rf "$APP_DIR"; ok "silindi"
  else
    info "birakildi"
  fi
fi
printf '\n%sKaldirma tamamlandi. Discord'"'"'u tamamen kapatip tekrar ac.%s\n' "$C_GREEN" "$C_OFF"
