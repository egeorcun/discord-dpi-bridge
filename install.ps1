#Requires -Version 5.1
<#
.SYNOPSIS
  discord-dpi-bridge kurulumu: Discord'u cekirdek surucusu OLMADAN DPI engelinden gecirir,
  boylece Denuvo/EAC gibi anti-cheat'ler WinDivert yuzunden oyunu reddetmez.
.DESCRIPTION
  Yaptiklari (hepsi geri alinabilir, uninstall.ps1 ile):
   1. GoodbyeDPI / WinDivert gibi cakisan servisleri bulur, onayla kaldirir
   2. Python'u kontrol eder (yoksa winget ile kurmayi teklif eder)
   3. ByeDPI'yi GitHub'dan indirir (kullanici alaninda SOCKS5 proxy)
   4. Windows'ta DNS over HTTPS acar (operatorun duz DNS'i ele gecirmesine karsi)
   5. hosts dosyasina updates.discord.com -> 127.0.0.1 yazar
   6. Acilista ByeDPI + kopruyu baslatan Startup girdisi olusturur ve hemen baslatir
   7. Discord kisayollarina --proxy-server bayragini ekler
   8. status.ps1 ile dogrular
  Yonetici yetkisi gerekir (kendisi UAC ile ister). -DryRun ile hicbir sey degistirmeden ne yapacagini gosterir.
.PARAMETER DryRun       Degisiklik yapma, sadece anlat.
.PARAMETER Yes          Sorulari sormadan evet say.
.PARAMETER AllowDnsFallback  DoH basarisiz olursa duz DNS'e dusmeye izin ver (guvenli ama engel geri gelebilir).
.PARAMETER SkipDoH      DNS ayarlarina dokunma.
.PARAMETER SkipHosts    hosts dosyasina dokunma.
.PARAMETER SkipDiscord  Discord kisayollarina dokunma.
.PARAMETER KeepConflicts  GoodbyeDPI/WinDivert'i kaldirmayi teklif etme.
.PARAMETER ByeDpiTag    Belirli bir ByeDPI surumu (ornek: v0.17.3). Bos = en yeni.
#>
[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Yes,
  [switch]$AllowDnsFallback,
  [switch]$SkipDoH,
  [switch]$SkipHosts,
  [switch]$SkipDiscord,
  [switch]$KeepConflicts,
  [string]$ByeDpiTag = ''
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------- yardimcilar ----------
function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "   [OK] $t" -ForegroundColor Green }
function Info($t) { Write-Host "   $t" }
function Warn($t) { Write-Host "   [!] $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "   [HATA] $t" -ForegroundColor Red }
function Ask($q) {
  if ($Yes) { return $true }
  $a = Read-Host "   $q [e/H]"
  return ($a -match '^(e|evet|y|yes)$')
}
function Act($desc, [scriptblock]$do) {
  if ($DryRun) { Info "(dry-run) $desc"; return $null }
  Info $desc
  return (& $do)
}
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------- yonetici yukseltme ----------
if (-not $DryRun -and -not (Test-Admin)) {
  $parts = @()
  foreach ($k in $PSBoundParameters.Keys) {
    $v = $PSBoundParameters[$k]
    if ($v -is [switch]) { if ($v.IsPresent) { $parts += "-$k" } }
    else { $parts += "-$k"; $parts += ('"' + $v + '"') }
  }
  Write-Host "Yonetici yetkisi gerekiyor; UAC penceresi acilacak..." -ForegroundColor Yellow
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" " + ($parts -join ' '))
  exit
}

$Root    = $PSScriptRoot
$Install = Join-Path $env:LOCALAPPDATA 'discord-dpi-bridge'
$Startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\discord-dpi-bridge.vbs'
$cfg     = Get-Content (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json

Write-Host "discord-dpi-bridge kurulum" -ForegroundColor Cyan
if ($DryRun) { Warn "DRY-RUN: hicbir sey degistirilmeyecek" }
Info "Kaynak : $Root"
Info "Hedef  : $Install"

# ---------- 1) cakisan suruculer ----------
Step "Cakisan cekirdek suruculeri"
$conflictSvcs = @('GoodbyeDPI', 'zapret', 'winws')
$found = @()
foreach ($n in $conflictSvcs) { if (Get-Service -Name $n -ErrorAction SilentlyContinue) { $found += $n } }
$drv = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'WinDivert' })
foreach ($d in $drv) { $found += $d.Name }
if ($found.Count -eq 0) { Ok "Cakisan servis/surucu yok" }
else {
  Warn ("Bulundu: " + ($found -join ', '))
  Info "Bunlar cekirdek seviyesinde paket mudahalesi yapar; Denuvo Anti-Cheat (ARC Raiders) ve benzerleri oyunu baslatmaz."
  if ($KeepConflicts) { Warn "KeepConflicts: dokunulmuyor. Oyun bunlar yukluyken acilmayacaktir." }
  elseif (Ask "Bu servisleri durdurup kaldirayim mi? (GoodbyeDPI klasorun silinmez, sadece Windows servisi kalkar)") {
    foreach ($n in $found) {
      Act "sc stop/delete $n" { & sc.exe stop $n 2>&1 | Out-Null; Start-Sleep -Milliseconds 800; & sc.exe delete $n 2>&1 | Out-Null } | Out-Null
    }
    Ok "Kaldirildi. Surucunun cekirdekten tamamen bosalmasi icin kurulum bitince YENIDEN BASLATMAN gerekir."
  } else { Warn "Kaldirilmadi. Oyun bunlar yukluyken acilmayacaktir." }
}

# ---------- 2) python ----------
Step "Python"
function Find-Python {
  $cands = @()
  if (Get-Command py.exe -ErrorAction SilentlyContinue) {
    try { $p = (& py -3 -c "import sys;print(sys.executable)" 2>$null); if ($p) { $cands += $p.Trim() } } catch {}
  }
  foreach ($n in 'python.exe', 'python3.exe') {
    $c = Get-Command $n -ErrorAction SilentlyContinue
    if ($c -and $c.Source -notmatch 'WindowsApps') { $cands += $c.Source }
  }
  $cands += Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  $cands += Get-ChildItem "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  foreach ($c in ($cands | Select-Object -Unique)) {
    if (-not (Test-Path $c)) { continue }
    try {
      $v = (& $c -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null)
      if ($v -and ([version]$v.Trim() -ge [version]'3.8')) { return $c }
    } catch {}
  }
  return $null
}
$python = Find-Python
if (-not $python) {
  Warn "Python 3.8+ bulunamadi (kopru icin gerekli)."
  if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
    if (Ask "winget ile Python 3.12 kurayim mi? (sadece bu kullanici icin, ~25 MB)") {
      Act "winget install Python.Python.3.12" { & winget install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements | Out-Null } | Out-Null
      $python = Find-Python
    }
  } else { Info "https://www.python.org/downloads/windows/ adresinden kur, sonra tekrar calistir." }
  if (-not $python -and -not $DryRun) { Fail "Python yok, devam edilemiyor."; exit 1 }
}
if ($python) {
  $pythonw = Join-Path (Split-Path $python) 'pythonw.exe'
  if (-not (Test-Path $pythonw)) { $pythonw = $python }
  Ok "Python: $python"
} else { $pythonw = 'pythonw.exe' }

# ---------- 3) dosyalar + ByeDPI ----------
Step "Dosyalar ve ByeDPI"
Act "Klasor: $Install" { New-Item -ItemType Directory -Force -Path $Install, (Join-Path $Install 'byedpi') | Out-Null } | Out-Null
foreach ($f in 'relay.py', 'config.json') {
  Act "kopyala $f" { Copy-Item (Join-Path $Root $f) (Join-Path $Install $f) -Force } | Out-Null
}
$ciadpi = Join-Path $Install 'byedpi\ciadpi.exe'
$verFile = Join-Path $Install 'byedpi\version.txt'
$haveVer = ''
if (Test-Path $verFile) { $haveVer = (Get-Content $verFile -Raw).Trim() }
$needDl = -not (Test-Path $ciadpi)
if ($ByeDpiTag -and $haveVer -ne $ByeDpiTag) { $needDl = $true }
if ($needDl) {
  try {
    $api = 'https://api.github.com/repos/hufrea/byedpi/releases/latest'
    if ($ByeDpiTag) { $api = "https://api.github.com/repos/hufrea/byedpi/releases/tags/$ByeDpiTag" }
    $rel = Invoke-RestMethod $api -Headers @{ 'User-Agent' = 'discord-dpi-bridge' }
    $asset = $rel.assets | Where-Object { $_.name -like '*x86_64-w64.zip' } | Select-Object -First 1
    if (-not $asset) { throw "surumde x86_64-w64 zip yok" }
    Info "ByeDPI $($rel.tag_name): $($asset.name)"
    Act "indir + ac" {
      $tmp = Join-Path $env:TEMP 'byedpi-dl'
      New-Item -ItemType Directory -Force -Path $tmp | Out-Null
      $zip = Join-Path $tmp $asset.name
      Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
      Expand-Archive $zip -DestinationPath $tmp -Force
      Copy-Item (Join-Path $tmp 'ciadpi.exe') $ciadpi -Force
      Set-Content $verFile $rel.tag_name
      Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } | Out-Null
    if (-not $DryRun -and -not (Test-Path $ciadpi)) {
      Fail "ciadpi.exe kopyalandi ama yerinde yok. Buyuk ihtimalle Windows Defender 'PUA' diye karantinaya aldi."
      Info "Windows Guvenligi > Virus ve tehdit korumasi > Koruma gecmisi'nden 'Cihazda izin ver' de, sonra install.ps1'i tekrar calistir."
      exit 1
    }
    Ok "ByeDPI hazir"
  } catch { Fail "ByeDPI indirilemedi: $($_.Exception.Message)"; Info "Elle: https://github.com/hufrea/byedpi/releases -> x86_64-w64.zip -> ciadpi.exe'yi $Install\byedpi\ icine koy."; if (-not $DryRun) { exit 1 } }
} else { Ok "ByeDPI zaten var ($haveVer)" }

# ---------- 4) DNS over HTTPS ----------
Step "DNS over HTTPS"
if ($SkipDoH) { Warn "SkipDoH: atlandi" }
else {
  $fb = 'no'; if ($AllowDnsFallback) { $fb = 'yes' }
  $servers = @($cfg.dns.v4) + @($cfg.dns.v6)
  foreach ($s in $servers) {
    Act "netsh dns encryption $s (udpfallback=$fb)" {
      & netsh dns add encryption server=$s dohtemplate=$($cfg.dns.template) autoupgrade=yes udpfallback=$fb 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { & netsh dns set encryption server=$s dohtemplate=$($cfg.dns.template) autoupgrade=yes udpfallback=$fb 2>&1 | Out-Null }
    } | Out-Null
  }
  $adapters = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
  if ($adapters.Count -eq 0) { Warn "Aktif (internete cikan) adaptor bulunamadi; DNS adaptor ayari atlandi" }
  $backup = Join-Path $Install 'dns-backup.json'
  if (-not (Test-Path $backup)) {
    $bk = @()
    foreach ($a in $adapters) {
      $bk += [pscustomobject]@{
        Alias = $a.InterfaceAlias; Index = $a.InterfaceIndex
        V4 = @((Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
        V6 = @((Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv6).ServerAddresses)
      }
    }
    Act "eski DNS ayarlarini yedekle -> dns-backup.json" { $bk | ConvertTo-Json -Depth 4 | Set-Content $backup -Encoding UTF8 } | Out-Null
  }
  foreach ($a in $adapters) {
    Act "adaptor '$($a.InterfaceAlias)': DNS = $($cfg.dns.v4 -join ', ')" {
      Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @($cfg.dns.v4)
      Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ServerAddresses @($cfg.dns.v6)
    } | Out-Null
  }
  Act "DNS onbellegini temizle" { Clear-DnsClientCache } | Out-Null
  Ok "DoH ayarlandi. Not: 'nslookup' DoH kullanmaz ve timeout verir; kontrol icin Resolve-DnsName kullan."
}

# ---------- 5) hosts ----------
Step "hosts dosyasi"
$hostsPath = "$env:WINDIR\System32\drivers\etc\hosts"
if ($SkipHosts) { Warn "SkipHosts: atlandi" }
else {
  $bakH = "$hostsPath.discord-dpi-bridge.bak"
  if (-not (Test-Path $bakH)) { Act "yedek -> hosts.discord-dpi-bridge.bak" { Copy-Item $hostsPath $bakH } | Out-Null }
  $lines = @(Get-Content $hostsPath)
  $out = @(); $skip = $false
  foreach ($l in $lines) {
    if ($l -eq '# >>> discord-dpi-bridge') { $skip = $true; continue }
    if ($l -eq '# <<< discord-dpi-bridge') { $skip = $false; continue }
    if (-not $skip) { $out += $l }
  }
  $out += '# >>> discord-dpi-bridge'
  foreach ($kv in $cfg.hosts_entries.map.PSObject.Properties) { $out += ("{0} {1}" -f $kv.Value, $kv.Name); Info ("{0} -> {1}" -f $kv.Name, $kv.Value) }
  $out += '# <<< discord-dpi-bridge'
  Act "hosts dosyasini yaz" { [IO.File]::WriteAllLines($hostsPath, $out) ; & ipconfig /flushdns | Out-Null } | Out-Null
  Ok "hosts guncellendi"
}

# ---------- 6) startup + baslat ----------
Step "Acilis girdisi ve baslatma"
$vbs = @"
' discord-dpi-bridge: ByeDPI (SOCKS5) + kopru. Kullanici alaninda calisir, cekirdek surucusu yok.
' install.ps1 tarafindan uretildi - elle duzenleme, install.ps1'i tekrar calistir.
Set sh = CreateObject("WScript.Shell")
base = "$Install\"
sh.CurrentDirectory = base
sh.Run """" & base & "byedpi\ciadpi.exe"" -i $($cfg.socks.host) -p $($cfg.socks.port) $($cfg.byedpi.args)", 0, False
WScript.Sleep 1500
sh.Run """$pythonw"" """ & base & "relay.py"" """ & base & "config.json""", 0, False
"@
Act "Startup: $Startup" { Set-Content -Path $Startup -Value $vbs -Encoding ASCII } | Out-Null
Act "eski ciadpi/relay sureclerini durdur" {
  Get-Process ciadpi -ErrorAction SilentlyContinue | Stop-Process -Force
  Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^python' -and $_.CommandLine -match 'relay\.py' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 1
} | Out-Null
Act "simdi baslat (wscript)" { Start-Process wscript.exe -ArgumentList "`"$Startup`""; Start-Sleep -Seconds 4 } | Out-Null
Ok "Acilista otomatik baslayacak"

# ---------- 7) discord ----------
Step "Discord kisayollari"
if ($SkipDiscord) { Warn "SkipDiscord: atlandi" }
elseif ($DryRun) { Info "(dry-run) fix-discord.ps1 -ProxyServer $($cfg.discord.proxy_server)" }
else { & (Join-Path $Root 'fix-discord.ps1') -ProxyServer $cfg.discord.proxy_server; Ok "Bayrak eklendi (Discord kendini guncelleyip silerse: fix-discord.ps1)" }

# ---------- 8) dogrula ----------
if (-not $DryRun) {
  Step "Dogrulama"
  & (Join-Path $Root 'status.ps1')
  $rc = $LASTEXITCODE
  Write-Host ''
  if ($found.Count -gt 0 -and -not $KeepConflicts) { Warn "Cakisan surucu kaldirildi -> simdi YENIDEN BASLAT, sonra Discord'u ve oyunu dene." }
  else { Info "Discord acikti ise tamamen kapatip (tepsiden de) masaustu kisayolundan tekrar ac." }
  exit $rc
}
Write-Host "`nDry-run bitti; degisiklik yapilmadi." -ForegroundColor Yellow
