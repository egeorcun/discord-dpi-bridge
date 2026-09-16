# discord-dpi-bridge

**Diğer dillerde oku:** **Türkçe** · [English](README.en.md)

**Türkiye'de Discord'a giremiyor ama GoodbyeDPI açıkken ARC Raiders gibi oyunlar açılmıyor mu?** Bu araç ikisini birden çözer: Discord açılır, oyun da açılır — çünkü hiçbir çekirdek sürücüsü yüklemez, anti-cheat'ler rahatsız olmaz.

---

## 🚀 Nasıl çalıştırılır (3 adım)

### 1) İndir
En kolayı: **[Releases sayfasından](https://github.com/egeorcun/discord-dpi-bridge/releases/latest)** `discord-dpi-bridge-vX.X.X.zip` dosyasını indir, sağ tıkla → **Tümünü ayıkla**.

> Git kullanıyorsan: `git clone https://github.com/egeorcun/discord-dpi-bridge`

### 2) Kur
Ayıkladığın klasörü aç. Boş bir yere **Shift + sağ tık** → **"PowerShell penceresini burada aç"**. Sonra şunu yapıştırıp Enter'a bas:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Ekranda **"Evet / Yönetici olarak çalıştır"** çıkarsa onayla. Kurulum her şeyi kendisi yapar (birkaç soru sorabilir, hepsine **E** diyebilirsin).

### 3) Bitince
- Kurulum "**yeniden başlat**" derse bilgisayarı yeniden başlat.
- Sonra **Discord'u masaüstü kısayolundan aç.** Hepsi bu. 🎉

Bundan sonra her açılışta kendiliğinden çalışır; bir daha uğraşman gerekmez.

---

## ✅ Çalışıyor mu diye bakmak

Aynı klasörde PowerShell açıp:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
```

Her şey **[OK]** ve altta **"Her şey yolunda"** yazıyorsa tamamdır.

## 🔧 Discord bir gün yine açılmazsa

Genelde **gerekmez** — arka plandaki gözcü, Discord güncellemelerinden sonra bunu otomatik düzeltir. Yine de olursa:

```powershell
powershell -ExecutionPolicy Bypass -File .\fix-discord.ps1
```

Sonra Discord'u kapatıp tekrar aç.

## 🗑️ Kaldırmak

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Yaptığı her şeyi geri alır (hosts, DNS, kısayollar, otomatik başlatma).


## 🍎 macOS

macOS sürümü ayrı bir klasörde: **[macos/README.md](macos/README.md)**. Aynı işi ByeDPI + sistem proxy (PAC) ile yapar; hosts/kısayol/gözcü gerekmez.

```bash
bash macos/install.sh
```

> Android için bu araç uyarlanamaz; orada [ByeByeDPI](https://github.com/romanvht/ByeByeDPI) uygulaması aynı işi (uygulama bazlı VPN modu, root gerekmez) yapar — `config.json` içindeki `byedpi.args` değerini oraya yapıştırabilirsin.

---

## Ne gerekiyor?

- **Windows 10 (21H2+) veya Windows 11** (macOS için: [macos/README.md](macos/README.md))
- Başka **hiçbir şey** — Python vs. gerekmez. Her şey Windows'ta hazır gelen PowerShell ile çalışır.
- Kurulumda bir kez yönetici izni ister (hosts + DNS ayarı için). Çalışırken hiçbir şey yönetici değildir.

## Neyi neden yapıyor? (kısaca)

GoodbyeDPI gibi araçlar engeli bir **çekirdek sürücüsüyle** (`WinDivert`) aşar; Denuvo/EAC gibi anti-cheat'ler bu sürücüyü görünce oyunu açmaz (ARC Raiders'ta "0x1: Yanlış işlev"). Bu araç aynı işi **sürücü olmadan** yapar:

1. **ByeDPI** — engeli kullanıcı seviyesinde aşan yerel proxy (sürücü yok).
2. **relay.ps1** — Discord'un güncelleyicisini de proxy'den geçiren köprü.
3. **DNS over HTTPS** — operatörün DNS engelini atlar.
4. **discord-guard** — Discord güncellenip ayarını bozduğunda otomatik onarır.

Kurulum GoodbyeDPI bulursa onu (senin onayınla) kaldırır; klasörünü silmez, sadece Windows servisini durdurur.

---

## Güvenlik ve doğrulama

- Bu depo/indirme **hiçbir çalıştırılabilir (.exe) dosya taşımaz.** Tek ikili olan `ciadpi.exe` (ByeDPI), kurulumda [ByeDPI'nin resmi sürümünden](https://github.com/hufrea/byedpi/releases) iner. Geri kalan her şey açık, okunabilir metin dosyasıdır.
- **Antivirüs "PUA/Riskware" derse:** ByeDPI bir engel-aşma aracı olduğu için bazı antivirüsler onu bu kategoriyle işaretler — bu bir virüs tespiti değildir. Windows Defender `ciadpi.exe`'yi silerse: Windows Güvenliği → Koruma geçmişi → **"Cihazda izin ver"**, sonra `install.ps1`'i tekrar çalıştır.

**VirusTotal (ByeDPI ikilisi, ByeDPI v0.17.3):**
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

Doğrulamak için: `Get-FileHash .\dosya -Algorithm SHA256`. Metin dosyalarının hash'i satır sonu ayarına duyarlıdır; en güvenilir doğrulama satır sonundan etkilenmeyen `ciadpi.exe`'dir.
</details>

## Sınırlar — dürüstçe

- Bu bir **kalıcı çözüm değil, geçici bir yoldur**; Discord kendi yapısını değiştirirse bozulabilir (gözcü çoğu durumu yakalar ama garanti değil).
- Sesli sohbet (UDP) proxy'den geçmez; genelde sorun olmaz ama operatöre göre değişebilir.
- Varsayılan ayarlar **Türk Telekom**'da doğrulandı. Başka operatörde `config.json` içindeki `byedpi.args`'ı ayarlaman gerekebilir ([ByeDPI](https://github.com/hufrea/byedpi)).
- DPI atlatmanın yasal durumu ülkeye göre değişir; kullanım sorumluluğu kullanıcıya aittir.

## Teşekkür

- [ByeDPI](https://github.com/hufrea/byedpi) (hufrea) — kullanıcı alanında DPI atlatmanın tamamı.
- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) (ValdikSS) — yıllarca iş gördü.

## Lisans

MIT. ByeDPI ayrı lisanslıdır (MIT) ve kurulumda ayrıca indirilir.

---

🇬🇧 **English:** see **[README.en.md](README.en.md)**.
