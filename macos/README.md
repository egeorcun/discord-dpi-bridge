# discord-dpi-bridge — macOS

**Diğer dillerde oku:** **Türkçe** · [English](README.en.md) · [Ana README](../README.md)

Windows sürümünün yaptığı işi macOS'ta yapar: Discord'u **çekirdek uzantısı yüklemeden**, kullanıcı seviyesinde çalışan [ByeDPI](https://github.com/hufrea/byedpi) üzerinden DPI engelinden geçirir. Yalnızca Discord alanları proxy'den geçer; geri kalan trafiğe dokunulmaz.

> ⚠️ Bu sürüm az sayıda gerçek Mac'te denendi. ByeDPI parametrelerinin operatöründe çalışması senin Mac'inde denenmelidir. Sorun görürsen [issue aç](https://github.com/egeorcun/discord-dpi-bridge/issues), `status.sh` çıktısını ekle.

---

## 🚀 Nasıl çalıştırılır (3 adım)

### 1) İndir
```bash
git clone https://github.com/egeorcun/discord-dpi-bridge
cd discord-dpi-bridge
```
(veya [Releases](https://github.com/egeorcun/discord-dpi-bridge/releases/latest) sayfasından `discord-dpi-bridge-macos-vX.Y.Z.zip`'i indir, aç ve Terminal'de o klasöre gir.)

### 2) Kur
```bash
bash macos/install.sh
```
- **Xcode Command Line Tools** yoksa kurulum bunu ister (tek seferlik, Apple'dan iner). Kurulunca betiği tekrar çalıştır.
- Ağ ayarları, `/etc/hosts` ve güncelleyici köprüsü için parolanı ister (`sudo`). Betiğin kendisini `sudo` ile çalıştırma.
- Sonda bir **DNS over HTTPS profili** açılır. macOS bunu komutla yüklemeye izin vermez; **Sistem Ayarları → Genel → Aygıt Yönetimi** (eski sürümlerde Gizlilik ve Güvenlik → Profiller) altında "discord-dpi-bridge: DNS over HTTPS" → **Yükle**.

### 3) Bitince
Discord açıksa **tamamen kapat** (Cmd+Q; menü çubuğundaki simgeden de Çıkış) ve tekrar aç. Hepsi bu.

Bundan sonra her açılışta kendiliğinden çalışır. Discord'a kısayol/bayrak gerekmez; uygulama sistem proxy ayarını, güncelleyicisi köprüyü kullanır. Güncellemeler bunu bozmaz.

---

## ✅ Çalışıyor mu diye bakmak
```bash
bash macos/status.sh
```
Her şey **[OK]** ve altta **"Her şey yolunda"** yazıyorsa tamamdır. `--no-network` ile internet gerektiren testler atlanır.

## 🗑️ Kaldırmak
```bash
bash macos/uninstall.sh
```
Yaptığı her şeyi geri alır: LaunchAgent'lar, güncelleyici köprüsü ve `/etc/hosts` girdileri, sistem proxy, DNS (yedekten), DoH profili, kurulum klasörü. `--keep-dns` ile DNS/DoH ayarı korunur.

---

## Ne gerekiyor?
- **macOS 12 (Monterey) veya üstü**, Intel ya da Apple Silicon.
- **Xcode Command Line Tools** (`xcode-select --install`). ByeDPI'nin resmi macOS ikilisi olmadığı için kaynaktan derlenir; derleyici, `git` ve `python3` buradan gelir. Başka **hiçbir şey** gerekmez (Homebrew vs. yok).

## Neyi neden yapıyor? (kısaca)
macOS'ta Discord (Electron) **sistem proxy ayarına uyar**, bu yüzden Windows'taki kısayol/gözcü parçalarına gerek kalmaz. Ama Discord'un **güncelleyicisi** (Rust) proxy/PAC ayarını okumaz; onun için Windows'taki hosts + köprü yöntemi kullanılır:

1. **ByeDPI** kaynaktan derlenir ve kullanıcı seviyesinde bir **LaunchAgent** olarak çalışır (SOCKS5 `127.0.0.1:1080`).
2. Yalnızca Discord alanlarını bu proxy'ye yönlendiren bir **PAC dosyası** üretilir ve `127.0.0.1:18080`'den sunulur (Chromium `file://` PAC kabul etmez).
3. `networksetup` ile tüm ağ servislerinin (Wi-Fi, Ethernet) **otomatik proxy yapılandırması** bu PAC'e ayarlanır.
4. **Güncelleyici köprüsü:** `updates.discord.com`, `stable.dl2.discordapp.net`, `dl.discordapp.net` `/etc/hosts` ile `127.0.0.1`'e çevrilir. `relay.py` bir **LaunchDaemon** olarak `127.0.0.1:443`'ü dinler, TLS'teki alan adına (SNI) bakar ve yalnızca bu alanları ByeDPI üzerinden gerçek sunucuya taşır. TLS'e dokunmaz; sertifika doğrulaması Discord'da kalır.
5. DNS Cloudflare'a çekilir ve **DNS over HTTPS profili** üretilir (operatörün düz DNS engeli için).

Kurulum klasörü: `~/Library/Application Support/discord-dpi-bridge/` (ByeDPI, PAC, loglar, ağ ayarı yedeği).

## Seçenekler
| `install.sh` | |
|---|---|
| `-y` | Soru sormadan devam et (profil için Enter beklemez) |
| `--dry-run` | Hiçbir şey değiştirme, ne yapacağını anlat |
| `--skip-dns` / `--skip-proxy` / `--skip-relay` | İlgili adımı atla |
| `--system-socks` | PAC yerine **sistem geneli SOCKS** proxy ayarla; sistem proxy'sine uyan tüm uygulamalar ByeDPI'den geçer (`--auto=torst` sayesinde engellenmeyen trafik olduğu gibi akar). |
| `--byedpi-tag vX.Y.Z` | Belirli bir ByeDPI sürümü (varsayılan: en yeni) |

`config.json` içindeki `macos` bölümünden proxy'ye giden alan adları (`proxy_domains`), köprüden geçen güncelleyici alanları (`relay_hosts`), PAC portu ve macOS'a özel ByeDPI parametreleri (`byedpi_args`, boşsa `byedpi.args` kullanılır) değiştirilebilir; sonra `install.sh`'i tekrar çalıştır.

## Sorun giderme
- **`status.sh` "discord.com (SOCKS5 üzerinden)" HATA veriyor:** ByeDPI parametreleri operatörüne uymuyor. `config.json → byedpi.args`'ı [ByeDPI README](https://github.com/hufrea/byedpi)'sine göre değiştir (macOS'ta `--disorder` davranışı Windows'tan farklı olabilir; `--split 1 --disorder 1 --auto=torst --tlsrec 1+s` ile başla). Sonra `bash macos/install.sh -y`.
- **Discord "Update failed — retrying" döngüsünde:** `status.sh`'te "Güncelleyici köprüsü" ve "güncelleme sunucusu (relay üzerinden)" satırlarına bak; HATA varsa `bash macos/install.sh -y`. Log: `~/Library/Application Support/discord-dpi-bridge/logs/relay.log`. Güncelleyicinin kendi logu: `~/Library/Application Support/discord/logs/Discord_updater_rCURRENT.log` (yeni bir alan adı görürsen `config.json → macos.relay_hosts`'a ekle).
- **DoH profili yüklenmiyor:** `open ~/Library/Application\ Support/discord-dpi-bridge/discord-dpi-bridge-doh.mobileconfig` ve Sistem Ayarları'ndan yükle.
- Loglar: `~/Library/Application Support/discord-dpi-bridge/logs/`.

## Güvenlik
- Bu klasörde **hiçbir çalıştırılabilir dosya yok**; ByeDPI senin Mac'inde, [resmi kaynağından](https://github.com/hufrea/byedpi) klonlanıp derlenir (sürüm etiketi `byedpi/version.txt`'de).
- `sudo` yalnızca `networksetup` (proxy/DNS), `/etc/hosts` ve köprü kurulumu için kullanılır. Köprü 443'ü açabilmek için root başlar, portu açar açmaz `nobody` kullanıcısına düşer. Betiği `/Library/Application Support/discord-dpi-bridge/` altında root'a ait tutulur (kullanıcı değiştiremez).
- Köprü yalnızca `127.0.0.1`/`::1`'de dinler ve yalnızca `relay_hosts`'taki alan adlarını taşır; başka SNI gelirse bağlantıyı kapatır.
- PAC sunucusu yalnızca `127.0.0.1`'de dinler ve sadece `proxy.pac` içeriğini döner.

<details>
<summary><b>Kaynak dosyaların SHA-256</b></summary>

| Dosya | SHA-256 |
|---|---|
| `install.sh` | `192fa3eb86a6a01ba93c4cf1b7eff582ee3950956e97623888ffebfb2f055ef4` |
| `uninstall.sh` | `0d4179c5fe61640ee31b74c5d5471864a49bff9545e70301b5c2c6cab0c2e2c7` |
| `status.sh` | `bfcbee809bdde54282bbf46d04a18822dc9b72bba7463c8e91e724e696eeed80` |
| `lib.sh` | `6770e354f2440755e8fe9568405ff8377ebb13a6447631d49a9fb4e472879dee` |
| `pac-server.py` | `360ec0a25f67f8361cdc90853c1be485a5e554b6a15c840faf65d21c3fe7f41f` |
| `relay.py` | `6a75f3e93abb84c7192bcf1ff4e319fcf3cb66088a797c0bd7eb19b67e45debc` |

Doğrulamak için: `shasum -a 256 macos/dosya`.
</details>

## Sınırlar — dürüstçe
- Windows sürümündeki tüm sınırlar burada da geçerli: geçici bir yol, Discord yapısını değiştirirse bozulabilir; sesli sohbet (UDP) proxy'den geçmez.
- Varsayılan ByeDPI parametreleri **Windows'ta Türk Telekom** için doğrulandı; macOS'ta aynı parametrelerin çalışması test edilmelidir.
- DoH profili adımı kullanıcı onayı ister; tam sessiz kurulum mümkün değil.
