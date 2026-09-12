#Requires -Version 5.1
<#
.SYNOPSIS
  discord-dpi-bridge'i kaldirir ve install.ps1'in yaptigi her seyi geri alir.
.DESCRIPTION
  - ByeDPI ve kopru sureclerini durdurur, Startup girdisini siler
  - hosts dosyasindaki discord-dpi-bridge blogunu kaldirir
  - DNS ayarlarini dns-backup.json'dan geri yukler ve DoH sablonlarini siler (-KeepDoH ile korunur)
  - Discord kisayollarindan --proxy-server bayragini kaldirir
  - Kurulum klasorunu siler (sorar)
  GoodbyeDPI'yi GERI KURMAZ; istersen kendi service_install*.cmd'ni calistirirsin.
.PARAMETER KeepDoH   DNS over HTTPS ayarini birak (zararsiz, genelde faydali).
.PARAMETER Yes       Sormadan evet say.
#>
[CmdletBinding()]
param([switch]$KeepDoH, [switch]$Yes)
$ErrorActionPreference = 'Continue'

function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "   [OK] $t" -ForegroundColor Green }
function Info($t) { Write-Host "   $t" }
function Warn($t) { Write-Host "   [!] $t" -ForegroundColor Yellow }
function Ask($q)  { if ($Yes) { return $true }; return ((Read-Host "   $q [e/H]") -match '^(e|evet|y|yes)$') }
function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-Admin)) {
  $parts = @(); foreach ($k in $PSBoundParameters.Keys) { if ($PSBoundParameters[$k].IsPresent) { $parts += "-$k" } }
  Write-Host "Yonetici yetkisi gerekiyor; UAC penceresi acilacak..." -ForegroundColor Yellow
  Start-Process powershell.exe -Verb RunAs -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" " + ($parts -join ' '))
  exit
}

$Root    = $PSScriptRoot
$Install = Join-Path $env:LOCALAPPDATA 'discord-dpi-bridge'
$Startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\discord-dpi-bridge.vbs'
$cfg     = Get-Content (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json

Step "Surecler ve Startup"
Get-Process ciadpi -ErrorAction SilentlyContinue | Stop-Process -Force
Get-CimInstance Win32_Process | Where-Object { ($_.Name -match '^python' -and $_.CommandLine -match 'relay\.py') -or ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'relay\.ps1|discord-guard\.ps1') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
if (Test-Path $Startup) { Remove-Item $Startup -Force }
Ok "durduruldu, Startup girdisi silindi"

Step "hosts dosyasi"
$hostsPath = "$env:WINDIR\System32\drivers\etc\hosts"
$out = @(); $skip = $false; $removed = 0
foreach ($l in (Get-Content $hostsPath)) {
  if ($l -eq '# >>> discord-dpi-bridge') { $skip = $true; continue }
  if ($l -eq '# <<< discord-dpi-bridge') { $skip = $false; continue }
  if ($skip) { $removed++; continue }
  $out += $l
}
[IO.File]::WriteAllLines($hostsPath, $out); & ipconfig /flushdns | Out-Null
Ok "$removed girdi kaldirildi"

Step "DNS"
if ($KeepDoH) { Info "KeepDoH: DNS ayarlari korunuyor" }
else {
  $backup = Join-Path $Install 'dns-backup.json'
  if (Test-Path $backup) {
    foreach ($b in (Get-Content $backup -Raw | ConvertFrom-Json)) {
      $a = Get-NetAdapter -InterfaceAlias $b.Alias -ErrorAction SilentlyContinue
      if (-not $a) { $a = Get-NetAdapter -InterfaceIndex $b.Index -ErrorAction SilentlyContinue }
      if (-not $a) { Warn "adaptor bulunamadi: $($b.Alias)"; continue }
      if ($b.V4 -and @($b.V4).Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses @($b.V4) }
      else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses }
      Info "'$($b.Alias)' DNS geri yuklendi: $(if ($b.V4) { $b.V4 -join ', ' } else { 'otomatik (DHCP)' })"
    }
  } else {
    foreach ($a in (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway })) {
      Set-DnsClientServerAddress -InterfaceIndex $a.InterfaceIndex -ResetServerAddresses
      Info "'$($a.InterfaceAlias)' DNS otomatik (DHCP) yapildi"
    }
  }
  foreach ($s in (@($cfg.dns.v4) + @($cfg.dns.v6))) { & netsh dns delete encryption server=$s 2>&1 | Out-Null }
  Clear-DnsClientCache
  Ok "DoH sablonlari silindi, DNS eski haline dondu"
}

Step "Discord kisayollari"
& (Join-Path $Root 'fix-discord.ps1') -Remove
Ok "bayrak kaldirildi"

Step "Kurulum klasoru"
if (Test-Path $Install) {
  if (Ask "$Install silinsin mi? (ByeDPI, kopru, loglar)") { Remove-Item $Install -Recurse -Force; Ok "silindi" } else { Info "birakildi" }
}
Write-Host "`nKaldirma tamamlandi. Discord'u tamamen kapatip tekrar ac." -ForegroundColor Green
