<#
.SYNOPSIS
  Discord kisayollarina ve otomatik baslatma kaydina --proxy-server bayragini ekler (veya kaldirir).
.DESCRIPTION
  Discord kendini guncelledikten sonra kisayollari sifirlayabilir; o zaman bunu tekrar calistir.
  Yonetici yetkisi GEREKMEZ.
.PARAMETER ProxyServer
  Chromium'a verilecek proxy (varsayilan: config.json -> discord.proxy_server).
.PARAMETER Remove
  Bayraklari kaldirir.
#>
[CmdletBinding()]
param(
  [string]$ProxyServer,
  [switch]$Remove,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if (-not $ProxyServer) {
  $cfgPath = Join-Path $PSScriptRoot 'config.json'
  if (Test-Path $cfgPath) { $ProxyServer = (Get-Content $cfgPath -Raw | ConvertFrom-Json).discord.proxy_server }
  if (-not $ProxyServer) { $ProxyServer = 'socks5://127.0.0.1:1080' }
}
$flag = "--proxy-server=$ProxyServer"
$psa  = "--process-start-args `"$flag`""
$changed = 0

function Say($m) { if (-not $Quiet) { Write-Host $m } }

# 1) HKCU Run kaydi (Discord'un "Windows ile baslat" ayari)
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$cur = (Get-ItemProperty $runKey -Name Discord -ErrorAction SilentlyContinue).Discord
if ($cur) {
  $new = $cur
  if ($Remove) {
    $new = ($cur -replace [regex]::Escape(" $psa"), '') -replace [regex]::Escape(" $flag"), ''
  } elseif ($cur -notmatch 'proxy-server') {
    if ($cur -match 'Update\.exe') { $new = "$cur $psa" } else { $new = "$cur $flag" }
  }
  if ($new -ne $cur) { Set-ItemProperty $runKey -Name Discord -Value $new; $changed++; Say "  [+] Run kaydi guncellendi" }
}

# 2) Kisayollar (masaustu + baslat menusu)
$sh = New-Object -ComObject WScript.Shell
$dirs = @("$env:USERPROFILE\Desktop", "$env:PUBLIC\Desktop",
          "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
          "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Discord Inc")
foreach ($d in $dirs) {
  if (-not (Test-Path $d)) { continue }
  foreach ($lnkPath in (Get-ChildItem $d -Filter 'Discord*.lnk' -ErrorAction SilentlyContinue)) {
    $lnk = $sh.CreateShortcut($lnkPath.FullName)
    if ($lnk.TargetPath -notmatch 'Discord') { continue }
    $args0 = $lnk.Arguments
    $args1 = $args0
    if ($Remove) {
      $args1 = ((($args0 -replace [regex]::Escape($psa), '') -replace [regex]::Escape($flag), '') -replace '\s{2,}', ' ').Trim()
    } elseif ($args0 -notmatch 'proxy-server') {
      if ($lnk.TargetPath -match 'Update\.exe') { $args1 = ("$args0 $psa").Trim() } else { $args1 = ("$args0 $flag").Trim() }
    }
    if ($args1 -ne $args0) {
      try { $lnk.Arguments = $args1; $lnk.Save(); $changed++; Say "  [+] $($lnkPath.FullName)" }
      catch { Say "  [!] Yazilamadi (yetki?): $($lnkPath.FullName)" }
    }
  }
}
if ($changed -eq 0) {
  if ($Remove) { Say "  [=] Degisiklik gerekmedi (bayrak yoktu)" } else { Say "  [=] Degisiklik gerekmedi (zaten ayarli)" }
}
exit 0
