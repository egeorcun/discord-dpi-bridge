# discord-dpi-bridge

**Diğer dillerde oku:** **Türkçe** · [English](README.en.md)

**Türkiye'de Discord açılmıyor mu?** Bu araç Discord'u **çekirdek sürücüsü yüklemeden** engelden geçirir. Windows'ta GoodbyeDPI yüzünden açılmayan anti-cheat'li oyunlar (ARC Raiders vb.) da açılır. **Windows ve macOS**'ta çalışır.

| | 🪟 Windows | 🍎 macOS |
|---|---|---|
| Gereken | Windows 10 (21H2+) / 11 | macOS 12+ (Intel veya Apple Silicon) |
| Ek program | Yok | Xcode Command Line Tools (kurulum kendisi ister) |
| Kur | `install.ps1` | `macos/install.sh` |
| Kontrol | `status.ps1` | `macos/status.sh` |
| Kaldır | `uninstall.ps1` | `macos/uninstall.sh` |

---

## 📥 İndir

**[Releases sayfasından](https://github.com/egeorcun/discord-dpi-bridge/releases/latest)** kendi sistemine ait zip'i indir ve aç:

- 🪟 Windows → `discord-dpi-bridge-windows-vX.Y.Z.zip`
- 🍎 macOS → `discord-dpi-bridge-macos-vX.Y.Z.zip`

Git kullanıyorsan (ikisi de aynı repoda):

```bash
git clone https://github.com/egeorcun/discord-dpi-bridge
```

---

## 🪟 Windows

### 1) Kur
Klasörü aç, boş bir yere **Shift + sağ tık → "PowerShell penceresini burada aç"**, şunu yapıştır:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

"Yönetici olarak çalıştır" sorusuna **Evet** de. Sorduğu her şeye **E** diyebilirsin.

### 2) Bitince
- Kurulum "**yeniden başlat**" derse bilgisayarı yeniden başlat.
- **Discord'u masaüstü kısayolundan aç.** Bitti. 🎉

Bundan sonra her açılışta kendiliğinden çalışır.

### Kontrol / düzelt / kaldır

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1        # çalışıyor mu? hepsi [OK] olmalı
powershell -ExecutionPolicy Bypass -File .\fix-discord.ps1   # Discord bir gün açılmazsa (genelde gerekmez, gözcü kendi düzeltir)
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1     # her şeyi geri al
```

---

## 🍎 macOS

### 1) Kur
Terminal'i aç, klasöre gir, şunu çalıştır:

```bash
bash macos/install.sh
```

- **Xcode Command Line Tools** yoksa macOS kurmayı teklif eder. Kurulunca komutu tekrar çalıştır.
- Parolanı ister (ağ ayarı, `/etc/hosts` ve güncelleyici köprüsü için). Komutun başına `sudo` **yazma**.
- Sonda bir **DNS profili** açılır: **Sistem Ayarları → Genel → Aygıt Yönetimi** → "discord-dpi-bridge: DNS over HTTPS" → **Yükle**.

### 2) Bitince
Discord açıksa **tamamen kapat** (Cmd+Q) ve tekrar aç. Bitti. 🎉

Her açılışta kendiliğinden çalışır. Kısayol veya ayar gerekmez; Discord güncellemeleri bozmaz. Hâlâ "Update failed" görürsen `bash macos/status.sh` çıktısına bak.

### Kontrol / kaldır

```bash
bash macos/status.sh      # çalışıyor mu? hepsi [OK] olmalı
bash macos/uninstall.sh   # her şeyi geri al
```

> ⚠️ macOS sürümü az sayıda gerçek Mac'te denendi. Sorun görürsen `status.sh` çıktısıyla [issue aç](https://github.com/egeorcun/discord-dpi-bridge/issues). Ayrıntılar ve seçenekler: **[macos/README.md](macos/README.md)**.

---

## 📱 Android?

Bu araç Android'e uyarlanamaz; orada zaten hazır bir uygulama var: **[ByeByeDPI](https://github.com/romanvht/ByeByeDPI)**. Root gerekmez, VPN modunda yalnızca Discord'u seçersin, oyunlara dokunmaz. Bu reponun `config.json` içindeki `byedpi.args` değerini oraya yapıştırabilirsin. DNS için: Ayarlar → Özel DNS → `one.one.one.one`.

---

## Nasıl çalışıyor? (kısaca)

GoodbyeDPI gibi araçlar engeli **çekirdek sürücüsüyle** (WinDivert) aşar; Denuvo/EAC gibi anti-cheat'ler bu sürücüyü görünce oyunu açmaz. Bu araç aynı işi **sürücü olmadan**, kullanıcı seviyesinde yapar. Çekirdek parça iki sistemde de aynı: [ByeDPI](https://github.com/hufrea/byedpi), yerel bir SOCKS5 proxy.

**Windows**
1. **ByeDPI** (`ciadpi.exe`) — engeli aşan yerel proxy.
2. **relay.ps1** — proxy kullanamayan Discord güncelleyicisini de proxy'den geçiren köprü (hosts dosyası ile).
3. **DNS over HTTPS** — operatörün DNS engelini atlar.
4. **discord-guard** — Discord güncellenip ayarını bozunca otomatik onarır.

**macOS**
1. **ByeDPI** — kaynaktan derlenir, LaunchAgent olarak çalışır.
2. **PAC dosyası** — yalnızca Discord alanlarını proxy'ye yönlendiren sistem proxy ayarı; Discord uygulaması buna uyar, kısayol ve gözcü gerekmez.
3. **relay.py** — Discord'un güncelleyicisi proxy/PAC ayarını okumaz; güncelleme alanları hosts ile yerel köprüye çevrilip ByeDPI'den geçirilir.
4. **DNS over HTTPS profili** — operatörün DNS engelini atlar.

Her şey geri alınabilir; `uninstall` betikleri eski ayarları yedekten döndürür.

---

## Güvenlik ve doğrulama

- Bu depo **hiçbir çalıştırılabilir dosya taşımaz.** Windows'ta `ciadpi.exe` kurulumda [ByeDPI'nin resmi sürümünden](https://github.com/hufrea/byedpi/releases) iner; macOS'ta ByeDPI senin Mac'inde resmi kaynağından derlenir. Geri kalan her şey açık, okunabilir metin dosyasıdır.
- **Antivirüs "PUA/Riskware" derse:** ByeDPI bir engel-aşma aracı olduğu için bazı antivirüsler onu bu kategoriyle işaretler; bu bir virüs tespiti değildir. Windows Defender `ciadpi.exe`'yi silerse: Windows Güvenliği → Koruma geçmişi → **"Cihazda izin ver"**, sonra `install.ps1`'i tekrar çalıştır.
- Yönetici izni yalnızca kurulumda (hosts, DNS, proxy ayarı) istenir. Windows'ta çalışırken hiçbir şey yönetici değildir; macOS'ta güncelleyici köprüsü 443 portunu açmak için root başlar ve hemen `nobody` kullanıcısına düşer.

**VirusTotal (ByeDPI ikilisi, v0.17.3):**
`ciadpi.exe` — SHA-256 `eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4`
→ https://www.virustotal.com/gui/file/eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4

<details>
<summary><b>Kaynak dosyaların SHA-256 (git clone ile alındığında)</b></summary>

| Dosya | SHA-256 |
|---|---|
| `relay.ps1` | `54d0f861842fcf18e03825a395056d486c46059c9bc6a17201004eb0e249ef98` |
| `discord-guard.ps1` | `91088481db498c9ade71406d690406920a0754a25a55059fa5ea6c5b8ab96c40` |
| `install.ps1` | `f3b2e4cc25bbe377c97e54b0efe6ef82f4ab1aabe5ca1661eb0b6a3ff6680575` |
| `uninstall.ps1` | `1d1f78ad7d9eb0e728b4e2e620df31d51f3fdb1e342643fb8e1fc5ae6e37e5aa` |
| `status.ps1` | `d1f535f6341e13805adbec4919fe8ecfc0ed53673c878348bb9cada9dbf4a703` |
| `fix-discord.ps1` | `2f195dbca2a222ff97e852f4069ab69f1f98e316f989fe587038bea9053c558e` |
| `config.json` | `0db3eadc2b76f9d00d2aad67e106180d9845424cbe6ddb4975d24961c6336596` |
| `macos/install.sh` | `278eaf0338421428d398649435725ea38066f8e2d92234265b967cc88aa266dc` |
| `macos/uninstall.sh` | `0d4179c5fe61640ee31b74c5d5471864a49bff9545e70301b5c2c6cab0c2e2c7` |
| `macos/status.sh` | `bfcbee809bdde54282bbf46d04a18822dc9b72bba7463c8e91e724e696eeed80` |
| `macos/lib.sh` | `6770e354f2440755e8fe9568405ff8377ebb13a6447631d49a9fb4e472879dee` |
| `macos/pac-server.py` | `360ec0a25f67f8361cdc90853c1be485a5e554b6a15c840faf65d21c3fe7f41f` |
| `macos/relay.py` | `6a75f3e93abb84c7192bcf1ff4e319fcf3cb66088a797c0bd7eb19b67e45debc` |

Windows: `Get-FileHash .\dosya -Algorithm SHA256` · macOS: `shasum -a 256 macos/dosya`. Metin dosyalarının hash'i satır sonu ayarına duyarlıdır; en güvenilir doğrulama `ciadpi.exe`'dir.
</details>

## Sınırlar — dürüstçe

- Bu **kalıcı çözüm değil, geçici bir yoldur**; Discord kendi yapısını değiştirirse bozulabilir.
- Sesli sohbet (UDP) proxy'den geçmez; genelde sorun olmaz ama operatöre göre değişebilir.
- Varsayılan ayarlar **Türk Telekom**'da (Windows) doğrulandı. Başka operatörde veya macOS'ta `config.json` içindeki `byedpi.args`'ı ayarlaman gerekebilir ([ByeDPI](https://github.com/hufrea/byedpi)).
- DPI atlatmanın yasal durumu ülkeye göre değişir; kullanım sorumluluğu kullanıcıya aittir.

## Teşekkür

- [ByeDPI](https://github.com/hufrea/byedpi) (hufrea) — kullanıcı alanında DPI atlatmanın tamamı.
- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) (ValdikSS) — yıllarca iş gördü.

## Lisans

MIT. ByeDPI ayrı lisanslıdır (MIT) ve kurulumda ayrıca indirilir/derlenir.
