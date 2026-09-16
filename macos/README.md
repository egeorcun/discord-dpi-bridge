# discord-dpi-bridge — macOS

**Diğer dillerde oku:** **Türkçe** · [English](README.en.md) · [Windows sürümü](../README.md)

Windows sürümünün yaptığı işi macOS'ta yapar: Discord'u **çekirdek uzantısı yüklemeden**, kullanıcı seviyesinde çalışan [ByeDPI](https://github.com/hufrea/byedpi) üzerinden DPI engelinden geçirir. Yalnızca Discord alanları proxy'den geçer; geri kalan trafiğe dokunulmaz.

> ⚠️ Bu sürüm **gerçek bir Mac'te henüz doğrulanmadı.** Betikler sahte bir macOS ortamında uçtan uca test edildi, ancak ByeDPI parametrelerinin operatöründe çalışması ve Discord'un güncelleyicisinin sistem proxy ayarına uyması senin Mac'inde denenmelidir. Sorun görürsen [issue aç](https://github.com/egeorcun/discord-dpi-bridge/issues), `status.sh` çıktısını ekle.

---

## 🚀 Nasıl çalıştırılır (3 adım)

### 1) İndir
```bash
git clone https://github.com/egeorcun/discord-dpi-bridge
cd discord-dpi-bridge
```
(veya [Releases](https://github.com/egeorcun/discord-dpi-bridge/releases/latest) zip'ini aç ve Terminal'de o klasöre gir.)

### 2) Kur
```bash
bash macos/install.sh
```
- **Xcode Command Line Tools** yoksa kurulum bunu ister (tek seferlik, Apple'dan iner). Kurulunca betiği tekrar çalıştır.
- Ağ ayarları için **bir kez** parolanı ister (`sudo`). Betiğin kendisini `sudo` ile çalıştırma.
- Sonda bir **DNS over HTTPS profili** açılır. macOS bunu komutla yüklemeye izin vermez; **Sistem Ayarları → Genel → Aygıt Yönetimi** (eski sürümlerde Gizlilik ve Güvenlik → Profiller) altında "discord-dpi-bridge: DNS over HTTPS" → **Yükle**.

### 3) Bitince
Discord açıksa **tamamen kapat** (Cmd+Q; menü çubuğundaki simgeden de Çıkış) ve tekrar aç. Hepsi bu.

Bundan sonra her açılışta kendiliğinden çalışır. Discord'a kısayol/bayrak gerekmez; sistem proxy ayarını kendisi kullanır, güncellemeler bunu bozmaz.

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
Yaptığı her şeyi geri alır: LaunchAgent'lar, sistem proxy, DNS (yedekten), DoH profili, kurulum klasörü. `--keep-dns` ile DNS/DoH ayarı korunur.

---

## Ne gerekiyor?
- **macOS 12 (Monterey) veya üstü**, Intel ya da Apple Silicon.
- **Xcode Command Line Tools** (`xcode-select --install`). ByeDPI'nin resmi macOS ikilisi olmadığı için kaynaktan derlenir; derleyici, `git` ve `python3` buradan gelir. Başka **hiçbir şey** gerekmez (Homebrew vs. yok).

## Neyi neden yapıyor? (kısaca)
macOS'ta hem Discord (Electron) hem de güncelleyicisi **sistem proxy ayarına uyar**. Bu yüzden Windows'taki hosts/köprü/kısayol/gözcü parçalarına gerek kalmaz:

1. **ByeDPI** kaynaktan derlenir ve kullanıcı seviyesinde bir **LaunchAgent** olarak çalışır (SOCKS5 `127.0.0.1:1080`).
2. Yalnızca Discord alanlarını bu proxy'ye yönlendiren bir **PAC dosyası** üretilir ve `127.0.0.1:18080`'den sunulur (Chromium `file://` PAC kabul etmez).
3. `networksetup` ile tüm ağ servislerinin (Wi-Fi, Ethernet) **otomatik proxy yapılandırması** bu PAC'e ayarlanır.
4. DNS Cloudflare'a çekilir ve **DNS over HTTPS profili** üretilir (operatörün düz DNS engeli için).

Kurulum klasörü: `~/Library/Application Support/discord-dpi-bridge/` (ByeDPI, PAC, loglar, ağ ayarı yedeği).

## Seçenekler
| `install.sh` | |
|---|---|
| `-y` | Soru sormadan devam et (profil için Enter beklemez) |
| `--dry-run` | Hiçbir şey değiştirme, ne yapacağını anlat |
| `--skip-dns` / `--skip-proxy` | İlgili adımı atla |
| `--system-socks` | PAC yerine **sistem geneli SOCKS** proxy ayarla. Discord güncelleyicisi PAC'e uymuyorsa yedek yol; sistem proxy'sine uyan tüm uygulamalar ByeDPI'den geçer (`--auto=torst` sayesinde engellenmeyen trafik olduğu gibi akar). |
| `--byedpi-tag vX.Y.Z` | Belirli bir ByeDPI sürümü (varsayılan: en yeni) |

`config.json` içindeki `macos` bölümünden proxy'ye giden alan adları (`proxy_domains`), PAC portu ve macOS'a özel ByeDPI parametreleri (`byedpi_args`, boşsa `byedpi.args` kullanılır) değiştirilebilir; sonra `install.sh`'i tekrar çalıştır.

## Sorun giderme
- **`status.sh` "discord.com (SOCKS5 üzerinden)" HATA veriyor:** ByeDPI parametreleri operatörüne uymuyor. `config.json → byedpi.args`'ı [ByeDPI README](https://github.com/hufrea/byedpi)'sine göre değiştir (macOS'ta `--disorder` davranışı Windows'tan farklı olabilir; `--split 1 --disorder 1 --auto=torst --tlsrec 1+s` ile başla). Sonra `bash macos/install.sh -y`.
- **Discord "güncelleme başarısız" döngüsünde:** güncelleyici PAC'i kullanmıyor olabilir → `bash macos/install.sh -y --system-socks`.
- **DoH profili yüklenmiyor:** `open ~/Library/Application\ Support/discord-dpi-bridge/discord-dpi-bridge-doh.mobileconfig` ve Sistem Ayarları'ndan yükle.
- Loglar: `~/Library/Application Support/discord-dpi-bridge/logs/`.

## Güvenlik
- Bu klasörde **hiçbir çalıştırılabilir dosya yok**; ByeDPI senin Mac'inde, [resmi kaynağından](https://github.com/hufrea/byedpi) klonlanıp derlenir (sürüm etiketi `byedpi/version.txt`'de).
- Çalışırken hiçbir şey root değildir. `sudo` yalnızca `networksetup` (proxy/DNS ayarı) için kullanılır.
- PAC sunucusu yalnızca `127.0.0.1`'de dinler ve sadece `proxy.pac` içeriğini döner.

<details>
<summary><b>Kaynak dosyaların SHA-256</b></summary>

| Dosya | SHA-256 |
|---|---|
| `install.sh` | `3c28025263506bef4d3a07c2128539a00c99d816fed6f6d84a7a5d90257b8919` |
| `uninstall.sh` | `9e728fcacbcb7e96efa8ab52611330bee2ebb0fba1dd6e4f9ecba073149ab7e5` |
| `status.sh` | `dff4db6ee3d43a5336af601dc98159280b45e78c17b51c87420de63e74b118f8` |
| `lib.sh` | `851277011c89ea3de1a161a188205f3c2a4fdf3c8ed1a67c03ab1d33eeef885d` |
| `pac-server.py` | `76fe793c7ebfaf3bffcfc53c7032c0866695f95d9c53ddd91280163cb662a57f` |

Doğrulamak için: `shasum -a 256 macos/dosya`.
</details>

## Sınırlar — dürüstçe
- Windows sürümündeki tüm sınırlar burada da geçerli: geçici bir yol, Discord yapısını değiştirirse bozulabilir; sesli sohbet (UDP) proxy'den geçmez.
- Varsayılan ByeDPI parametreleri **Windows'ta Türk Telekom** için doğrulandı; macOS'ta aynı parametrelerin çalışması test edilmelidir.
- DoH profili adımı kullanıcı onayı ister; tam sessiz kurulum mümkün değil.
