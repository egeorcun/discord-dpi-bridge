<#
.SYNOPSIS
  discord-dpi-bridge saglik kontrolu. Yonetici GEREKMEZ.
.DESCRIPTION
  Her bileseni tek tek test eder ve sorun varsa nerede oldugunu soyler.
  Cikis kodu 0 = her sey yolunda, 1 = sorun var.
.PARAMETER NoNetwork
  Internet gerektiren testleri atlar.
#>
[CmdletBinding()]
param([switch]$NoNetwork)
$ErrorActionPreference = 'SilentlyContinue'
$cfg = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
$script:problems = 0

function Row([object]$ok, [string]$name, [string]$detail) {
  # $ok: $true / $false / 'info' (bilgi satiri, sayilmaz)
  if ($ok -is [string] -and $ok -eq 'info') { $mark = '[--]  '; $color = 'DarkGray' }
  elseif ([bool]$ok) { $mark = '[OK]  '; $color = 'Green' }
  else { $mark = '[HATA]'; $color = 'Red'; $script:problems++ }
  Write-Host ("  {0} {1,-36} {2}" -f $mark, $name, $detail) -ForegroundColor $color
}

Write-Host "`ndiscord-dpi-bridge durum`n" -ForegroundColor Cyan

# --- 1) Cakisan cekirdek suruculeri
Write-Host "Cakisan suruculer" -ForegroundColor Yellow
$bad = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.State -eq 'Running' -and $_.Name -match 'WinDivert' })
if ($bad.Count -gt 0) { Row $false 'WinDivert (GoodbyeDPI/zapret)' ("CALISIYOR: " + ($bad.Name -join ', ') + " -> anti-cheat bunu reddeder") }
else { Row $true 'WinDivert (GoodbyeDPI/zapret)' 'yuklu degil' }
$svc = Get-Service -Name GoodbyeDPI
if ($null -ne $svc) { Row $false 'GoodbyeDPI servisi' "kayitli ($($svc.Status)) -> kaldirilmali" } else { Row $true 'GoodbyeDPI servisi' 'yok' }

# --- 2) ByeDPI
Write-Host "`nByeDPI (SOCKS5 proxy)" -ForegroundColor Yellow
$p = @(Get-Process ciadpi)
if ($p.Count -gt 0) { Row $true 'ciadpi.exe sureci' "PID $($p.Id -join ',')" } else { Row $false 'ciadpi.exe sureci' 'calismiyor' }
$l = @(Get-NetTCPConnection -LocalPort $cfg.socks.port -State Listen)
if ($l.Count -gt 0) { Row $true "port $($cfg.socks.port) dinleniyor" $l[0].LocalAddress } else { Row $false "port $($cfg.socks.port) dinleniyor" 'hayir' }

# --- 3) Kopru
Write-Host "`nKopru (relay.ps1)" -ForegroundColor Yellow
$rp = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'relay\.ps1' })
if ($rp.Count -gt 0) { Row $true 'relay.ps1 sureci' "PID $($rp.ProcessId -join ',')" } else { Row $false 'relay.ps1 sureci' 'calismiyor' }
foreach ($r in $cfg.routes) {
  $lp = $r.port; if ($r.listen_port) { $lp = $r.listen_port }
  $ok = @(Get-NetTCPConnection -LocalAddress $r.listen -LocalPort $lp -State Listen)
  if ($ok.Count -gt 0) { Row $true "$($r.listen):$lp -> $($r.host)" 'dinleniyor' } else { Row $false "$($r.listen):$lp -> $($r.host)" 'dinlenmiyor' }
}

# --- 4) hosts
Write-Host "`nHosts dosyasi" -ForegroundColor Yellow
$hosts = Get-Content "$env:WINDIR\System32\drivers\etc\hosts"
foreach ($kv in $cfg.hosts_entries.map.PSObject.Properties) {
  $pat = "^\s*" + [regex]::Escape($kv.Value) + "\s+" + [regex]::Escape($kv.Name) + "\s*$"
  $ok = @($hosts | Where-Object { $_ -match $pat })
  if ($ok.Count -gt 0) { Row $true $kv.Name "-> $($kv.Value)" } else { Row $false $kv.Name 'girdi yok (install.ps1 yonetici olarak)' }
}

# --- 5) DoH
Write-Host "`nDNS over HTTPS" -ForegroundColor Yellow
$want = @($cfg.dns.v4) + @($cfg.dns.v6)
$doh = @(Get-DnsClientDohServerAddress | Where-Object { $want -contains $_.ServerAddress -and $_.AutoUpgrade })
if ($doh.Count -gt 0) { Row $true 'DoH sablonu (autoupgrade)' ($doh.ServerAddress -join ', ') } else { Row $false 'DoH sablonu (autoupgrade)' 'kayitli degil' }
$act = @(Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
foreach ($a in $act) {
  $srv = @((Get-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4).ServerAddresses)
  $hit = @($srv | Where-Object { $cfg.dns.v4 -contains $_ })
  Row ($hit.Count -gt 0) "adaptor '$($a.InterfaceAlias)' DNS" ($srv -join ', ')
}

# --- 6) Discord bayraklari
Write-Host "`nDiscord" -ForegroundColor Yellow
$run = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name Discord).Discord
if ($run -match 'proxy-server') { Row $true 'otomatik baslatma kaydi' 'proxy bayragi var' }
elseif ($run) { Row $false 'otomatik baslatma kaydi' 'bayrak YOK -> fix-discord.ps1' }
else { Row 'info' 'otomatik baslatma kaydi' 'kayit yok' }
$sh = New-Object -ComObject WScript.Shell
$lnk = Get-Item "$env:USERPROFILE\Desktop\Discord.lnk"
if ($null -ne $lnk) {
  $a = $sh.CreateShortcut($lnk.FullName).Arguments
  if ($a -match 'proxy-server') { Row $true 'masaustu kisayolu' 'proxy bayragi var' } else { Row $false 'masaustu kisayolu' 'bayrak YOK -> fix-discord.ps1' }
}
$upd = "$env:APPDATA\discord\logs\Discord_updater_rCURRENT.log"
if (Test-Path $upd) {
  $err = Get-Content $upd | Select-String -CaseSensitive 'ERROR' | Select-Object -Last 1
  if ($null -eq $err) { Row $true 'guncelleyici logu' 'hata yok' }
  else {
    $m = $err.Line -replace '.*source: ', ''
    if ($m.Length -gt 90) { $m = $m.Substring(0, 90) + '...' }
    Row $false 'guncelleyici logu' $m
  }
}

# --- 7) Ag testleri
if (-not $NoNetwork) {
  Write-Host "`nAg testleri" -ForegroundColor Yellow
  $curl = Get-Command curl.exe
  if ($null -ne $curl) {
    $t1 = & curl.exe -s -m 15 -o NUL -w '%{http_code}' --socks5-hostname "$($cfg.socks.host):$($cfg.socks.port)" 'https://discord.com/api/v9/gateway'
    Row ($t1 -eq '200') 'discord.com (SOCKS5 uzerinden)' "HTTP $t1"
    $t2 = & curl.exe -s -m 15 -o NUL -w '%{http_code}' 'https://updates.discord.com/distributions/app/manifests/latest?channel=stable&platform=win&arch=x64'
    Row ($t2 -eq '200') 'updates.discord.com (hosts->kopru)' "HTTP $t2"
    $t3 = & curl.exe -s -m 10 -o NUL -w '%{http_code}' 'https://discord.com/'
    if ($t3 -eq '200') { Row 'info' 'discord.com (dogrudan, bilgi)' 'HTTP 200 (ECH/DoH sayesinde olabilir)' } else { Row 'info' 'discord.com (dogrudan, bilgi)' "HTTP $t3 (engelli - beklenen)" }
  } else { Row 'info' 'curl.exe' 'bulunamadi, ag testi atlandi' }
  try {
    $sys = @((Resolve-DnsName discord.com -Type A | Where-Object IPAddress).IPAddress)
    $ans = (Invoke-RestMethod "$($cfg.doh.url)?name=discord.com&type=A" -Headers @{accept='application/dns-json'}).Answer
    $real = @($ans | Where-Object { $_.type -eq 1 } | ForEach-Object { $_.data })
    $poison = @($sys | Where-Object { $real -notcontains $_ })
    if ($poison.Count -eq 0) { Row $true 'DNS zehirlenmesi' 'yok (sistem = DoH)' } else { Row $false 'DNS zehirlenmesi' "sistem $($poison -join ',') donuyor, gercek: $($real -join ',')" }
  } catch { Row 'info' 'DNS karsilastirma' 'yapilamadi' }
}

Write-Host ''
if ($script:problems -eq 0) { Write-Host "Her sey yolunda." -ForegroundColor Green; exit 0 }
Write-Host "$($script:problems) sorun bulundu." -ForegroundColor Red
exit 1
