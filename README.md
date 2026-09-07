# discord-dpi-bridge

**Türkiye'de Discord'a girmek için GoodbyeDPI kullanıyorsun ama anti-cheat'li oyunlar (ARC Raiders, vb.) açılmıyor mu?** Bu araç tam o sorun için.

GoodbyeDPI ve zapret gibi araçlar DPI engelini **çekirdek seviyesinde** bir sürücüyle (`WinDivert64.sys`) aşar. Denuvo Anti-Cheat, EAC gibi anti-cheat'ler bu tür paket müdahale sürücülerini gördüğünde oyunu başlatmayı reddeder — ARC Raiders'ta bu "Oyun çöktü, 0x1: Yanlış işlev" hatası olarak görünür.

**discord-dpi-bridge** aynı işi **hiç çekirdek sürücüsü yüklemeden** yapar. Discord çalışır, oyun çalışır, ikisi aynı anda çalışır.

> English summary at the bottom.

---

## Nasıl çalışıyor

Discord tek bir program değil, iki ayrı ağ istemcisi taşıyor ve ikisi farklı davranıyor:

| Bileşen | Ne | Proxy kullanır mı |
|---|---|---|
| Sohbet / uygulama | Chromium | ✅ `--proxy-server` bayrağıyla |
| **Güncelleyici** | Rust (`reqwest`) | ❌ Hiçbir ayarla — doğrudan bağlanır |

Bu yüzden dört parça var:

```
                     ┌──────────────────────────────────────────────┐
 Discord (Chromium) ─┤ --proxy-server=socks5://127.0.0.1:1080        │
                     │        │                                       │
 Discord updater ────┤ hosts: updates.discord.com → 127.0.0.1:443    │
                     │        │  relay.py (TCP→SOCKS5 köprüsü)        │
                     │        ▼                                       │
                     │   ByeDPI (ciadpi.exe) SOCKS5, kullanıcı alanı  │──▶ internet
                     │                                                │
 Windows DNS ────────┤ DNS over HTTPS (Cloudflare) — 53/udp'yi        │
                     │ ele geçiren operatör DNS'ini atlar             │
                     └──────────────────────────────────────────────┘
```

1. **ByeDPI** — DPI atlatmayı kullanıcı alanında yapan yerel SOCKS5 proxy. Sürücü yok.
2. **relay.py** — Proxy kullanamayan güncelleyici için köprü. hosts dosyası `updates.discord.com`'u `127.0.0.1`'e yönlendirir; köprü o portu dinler ve bağlantıyı ByeDPI üzerinden gerçek sunucuya taşır. TLS'e dokunmaz, sertifika doğrulaması olduğu gibi kalır.
3. **DNS over HTTPS** — Operatör düz DNS sorgularını şeffaf şekilde ele geçirip engel sayfası IP'si (`195.175.254.2`) döndürüyor; `1.1.1.1` yazmak yetmiyor. DoH bunu bitirir.
4. **Discord bayrağı** — Kısayollara ve "Windows ile başlat" kaydına `--proxy-server` eklenir.

Hepsi yeniden başlatmada kendiliğinden gelir (Startup klasöründe bir `.vbs`).

## Gereksinimler

- Windows 10 21H2+ / Windows 11 (DoH desteği için)
- Python 3.8+ (yoksa kurulum betiği winget ile kurmayı teklif eder)
- Yönetici yetkisi — sadece kurulumda (hosts + DNS için); çalışma zamanında hiçbir şey yönetici değildir

## Kurulum

```powershell
git clone https://github.com/egeorcun/discord-dpi-bridge
cd discord-dpi-bridge
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

UAC penceresini onayla. Betik sırayla:

1. GoodbyeDPI / WinDivert bulursa **sorar** ve kaldırır (klasörüne dokunmaz, sadece Windows servisini siler)
2. Python'u kontrol eder
3. ByeDPI'yi GitHub'dan indirir (`%LOCALAPPDATA%\discord-dpi-bridge\byedpi\`)
4. DoH'u açar, DNS'i Cloudflare yapar (eskisini `dns-backup.json`'a yedekler)
5. hosts dosyasına yazar (yedek: `hosts.discord-dpi-bridge.bak`)
6. Startup girdisini oluşturur ve hemen başlatır
7. Discord kısayollarını düzenler
8. `status.ps1` ile doğrular

GoodbyeDPI kaldırıldıysa **bilgisayarı yeniden başlat** — sürücü ancak öyle boşalır.

Önce ne yapacağını görmek istersen: `.\install.ps1 -DryRun` (yönetici gerektirmez, hiçbir şeyi değiştirmez).

## Kontrol

```powershell
.\status.ps1
```

Her parçayı ayrı test eder ve nerede takıldığını söyler. Bir şey bozulduğunda ilk bakılacak yer bu.

## Discord güncellenince bozulursa

Discord kendini güncellediğinde kısayolları sıfırlayabiliyor. Discord açılmıyorsa:

```powershell
.\fix-discord.ps1
```

Yönetici gerekmez.

## Kaldırma

```powershell
.\uninstall.ps1
```

hosts, DNS, Startup, Discord bayrakları — hepsini geri alır. DoH'u tutmak istersen `-KeepDoH`. GoodbyeDPI'yi geri kurmaz.

## Sık sorulanlar

**Windows Defender `ciadpi.exe`'yi karantinaya aldı.**
ByeDPI'nin bilinen bir yanlış pozitifi (PUA). Windows Güvenliği → Koruma geçmişi → "Cihazda izin ver", sonra `install.ps1`'i tekrar çalıştır.

**`nslookup discord.com` timeout veriyor.**
Normal. `nslookup` ham UDP gönderir, DoH kullanmaz. Doğru kontrol: `Resolve-DnsName discord.com`.

**Discord güncelleyici hâlâ dönüyor.**
`status.ps1` çalıştır. `%APPDATA%\discord\logs\Discord_updater_rCURRENT.log` içinde hangi alan adına takıldığına bak; `updates.discord.com` ve `dl.discordapp.net` dışında bir şeyse `config.json`'daki `routes` ve `hosts_entries.map`'e ekleyip `install.ps1`'i tekrar çalıştır.

**Discord açılıyor ama bazı şeyler yüklenmiyor / ses yok.**
Ses (UDP) proxy'den geçmez, doğrudan gider; genelde bu sorun olmaz çünkü engel alan adı bazlı. Çalışmıyorsa `config.json` → `byedpi.args`'ı operatörüne göre ayarlamak gerekebilir ([ByeDPI README](https://github.com/hufrea/byedpi)).

**Bu ayarlar hangi operatörde çalışır?**
Varsayılan `byedpi.args` Türk Telekom'da test edildi. Farklı operatörde ByeDPI parametrelerini değiştirmen gerekebilir; DoH ve köprü kısmı operatörden bağımsızdır.

**Başka oyunlar / başka anti-cheat'ler?**
Buradaki hiçbir parça çekirdek sürücüsü yüklemediği için anti-cheat'lerin görebileceği bir şey yok. Denuvo Anti-Cheat (ARC Raiders) ile doğrulandı. Ama her anti-cheat'i test etmedim; sorumluluk sende.

**`udpfallback=no` ne demek, tehlikeli mi?**
DoH başarısız olursa Windows zehirlenmiş düz DNS'e **geri dönmez** — engel geri gelmesin diye. Yan etkisi: `1.1.1.1`'e HTTPS erişimi kesilirse DNS tamamen susar. Bunu istemiyorsan `install.ps1 -AllowDnsFallback`.

**VPN kullansam olmaz mıydı?**
Olur, ama iki bedeli var: tüm oyun trafiği tünelden geçer (ping artar) ya da split tunneling gerekir — Proton VPN gibi istemcilerin split tunneling'i de WFP callout sürücüsü yüklüyor, o da anti-cheat açısından WinDivert'e benzer risk taşıyor.

## Güvenlik ve doğrulama

- Bu depo **hiçbir ikili (çalıştırılabilir) dosya taşımaz.** Tek ikili olan `ciadpi.exe` (ByeDPI), kurulum sırasında [ByeDPI'nin resmi GitHub sürümünden](https://github.com/hufrea/byedpi/releases) iner; `install.ps1` indirdiği sürümü `byedpi\version.txt`'e yazar. Geri kalan her şey okunabilir kaynak koddur (`.ps1`, `.py`) — indir, aç, oku.
- **Neden antivirüs "PUA/HackTool" diyor?** ByeDPI bir DPI atlatma aracı olduğu için bazı motorlar onu "Riskware / PUA / HackTool / not-a-virus" diye işaretler. Bu bir **zararlı yazılım tespiti değil, kategori uyarısıdır** — aracın ne yaptığına bakıp koydukları etiket. ByeDPI açık kaynaktır, kodu incelenebilir. Windows Defender `ciadpi.exe`'yi karantinaya alırsa: Windows Güvenliği → Koruma geçmişi → "Cihazda izin ver", sonra `install.ps1`'i tekrar çalıştır.

### VirusTotal — `ciadpi.exe`

Doğrulanan sürüm: **ByeDPI v0.17.3**, `byedpi-17.3-x86_64-w64.zip` içindeki `ciadpi.exe`.

| Alan | Değer |
|---|---|
| SHA-256 | `eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4` |
| Boyut | 129 024 bayt |
| VirusTotal | **https://www.virustotal.com/gui/file/eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4** |

> Bağlantı, dosyanın **o an geçerli** VirusTotal taramasını gösterir (oran zamanla değişebilir). DPI araçları için birkaç motorun "PUA/Riskware" işaretlemesi beklenen bir durumdur; önemli olan tespitin türü, sayısı değil. Bu SHA-256, ByeDPI'nin resmi sürümündeki `ciadpi.exe` ile aynıdır — yani üst(upstream) ile birebir doğrulayabilirsin.

### Kaynak dosyalar (bütünlük)

Aşağıdakiler bu deponun kendi kaynak dosyaları. `git clone` ile alındıklarında (satır sonları `.gitattributes` ile sabitlenir: `.ps1` = CRLF, `.py`/`.json` = LF) SHA-256'ları:

| Dosya | SHA-256 |
|---|---|
| `relay.py` | `9160ed3cf13e71c3d979279e7400ed75ab9720c88e4377cec842d302d60ceba8` |
| `install.ps1` | `5aa1588a88c2dad6e29204ed3c4ad5db5c49db4ad0a0c80716721a9af651b2c0` |
| `uninstall.ps1` | `c6042baf68d75f7f936a36f21bcb9b1e7ba9d581031ce15bcf3fcefb2508c1b6` |
| `status.ps1` | `00deae470c8ebaf0d3da8baa46a25bc068904a4a38192e176b2853e27067bd7b` |
| `fix-discord.ps1` | `2f195dbca2a222ff97e852f4069ab69f1f98e316f989fe587038bea9053c558e` |
| `config.json` | `43da260d90a56ff8886e94b5664774241d4d934f61a598db88f4365e31b37c5d` |

Kendi indirdiğin dosyayı doğrulamak için:

```powershell
Get-FileHash .\ciadpi.exe -Algorithm SHA256   # ByeDPI ikili — yukaridaki ile karsilastir
Get-FileHash .\relay.py   -Algorithm SHA256
```

> Not: Bu betikler bu deponun yeni dosyaları; VirusTotal'da henüz taranmamış olabilirler. İstersen kendin yükleyip tarat — hepsi düz metin, gizli bir şey yok. Metin dosyalarının hash'i satır sonu ayarına duyarlıdır; şüphede kalırsan `git clone` ile al ya da dosyayı doğrudan oku. İkili `ciadpi.exe`'nin hash'i satır sonundan etkilenmez, en güvenilir doğrulama noktası odur.

## Sınırlar — dürüstçe

- Bu bir **çözüm değil, geçici yol**. Discord istemcisini değiştirdiğinde (yeni bir alan adı, güncelleyicinin davranışı) kırılabilir.
- Chromium tarafı ECH (şifreli SNI) + DoH ile bazen proxy'siz de bağlanabiliyor; buna güvenilmedi çünkü operatör istediği an ECH'i kesebilir.
- `relay.py` yalnızca IPv4 hedefleri çözer.
- DPI atlatma araçlarının hukuki durumu ülkeye göre değişir. Bu araç bir iletişim uygulamasına erişmek içindir; yerel mevzuat ve hizmet şartlarına uyum kullanıcının sorumluluğundadır.

## Teşekkür

- [ByeDPI](https://github.com/hufrea/byedpi) — hufrea. Kullanıcı alanında DPI atlatmanın tamamı onun işi.
- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) — ValdikSS. Sorunu yaşayana kadar yıllarca işimizi gördü.

## Lisans

MIT. ByeDPI ayrı lisanslıdır (MIT) ve kurulumda ayrıca indirilir; bu depoda barındırılmaz.

---

## English summary

**Problem.** In Turkey, Discord is DPI-blocked. The usual fix (GoodbyeDPI / zapret) works via the `WinDivert64.sys` kernel packet-interception driver — which kernel anti-cheats (Denuvo Anti-Cheat, EAC, …) refuse to coexist with. ARC Raiders shows this as "Game crashed, 0x1: Incorrect function."

**What this does.** Reaches Discord with **no kernel driver at all**, so the game and Discord run side by side:

1. **ByeDPI** — user-space SOCKS5 proxy doing the DPI desync.
2. **relay.py** — Discord's updater is a separate Rust/`reqwest` client that ignores every proxy setting (Chromium flag, `HTTPS_PROXY`, `settings.json`). So `hosts` points `updates.discord.com` at a loopback address, and this bridge forwards that TCP connection through ByeDPI to the real server. TLS is untouched; certificate validation stays intact. The bridge resolves the real IP via DoH and hands SOCKS5 an **IP**, not a hostname — otherwise ByeDPI would resolve the hosts entry and loop back into the bridge.
3. **DNS over HTTPS** — the ISP transparently hijacks plain port-53 DNS and returns a block-page IP; setting `1.1.1.1` alone doesn't help.
4. **`--proxy-server`** added to Discord's shortcuts and Run key.

`install.ps1` (self-elevates; `-DryRun` to preview), `status.ps1` (health check, no admin), `fix-discord.ps1` (re-apply flags after a Discord update), `uninstall.ps1` (reverts everything). Config in `config.json`. Requires Windows 10 21H2+/11 and Python 3.8+ (installer offers to install it via winget).

Tested on Türk Telekom with Denuvo Anti-Cheat (ARC Raiders). Other ISPs may need different `byedpi.args`. This is a workaround, not a fix; it may break when Discord changes its client. Legal status of DPI circumvention varies by country — compliance is the user's responsibility.
