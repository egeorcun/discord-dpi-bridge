<#
  discord-dpi-bridge guard

  Discord kendini guncelledikce kisayollardaki ve settings.json'daki
  --proxy-server bayragini siler; o zaman Discord proxy'siz baslar ve
  (DPI engeli yuzunden) acilmaz. Bu gozcu arka planda calisir, boyle bir
  durumu fark edince kisayollari tazeler ve Discord'u proxy ile yeniden
  baslatir. Boylece kullanicinin her guncellemede elle mudahale etmesi
  gerekmez.

  ONEMLI: yalnizca proxy bayragi EKSIK olan (yani zaten bozuk/baglanamayan)
  Discord'a mudahale eder. Duzgun calisan bir oturuma asla dokunmaz.

  Yalnizca Windows'ta yerlesik PowerShell ile calisir. Python gerekmez.
  Kullanim: powershell -NoProfile -ExecutionPolicy Bypass -File discord-guard.ps1 [config.json]
#>
param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
$ConfigPath = (Resolve-Path $ConfigPath).Path
$cfg        = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$Proxy      = $cfg.discord.proxy_server
if (-not $Proxy) { $Proxy = 'socks5://127.0.0.1:1080' }
$Flag       = "--proxy-server=$Proxy"
$LogPath    = Join-Path (Split-Path -Parent $ConfigPath) 'guard.log'
$LogMax     = 2MB
$UpdateExe  = Join-Path $env:LOCALAPPDATA 'Discord\Update.exe'
$FixScript  = Join-Path $PSScriptRoot 'fix-discord.ps1'
$PollSec    = 5
$CooldownSec = 30          # iki mudahale arasi en az sure (hammer korumasi)
$lastFix    = [datetime]::MinValue

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try {
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt $LogMax) { Move-Item $LogPath "$LogPath.old" -Force }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch { }
}

Write-Log "guard basladi (flag: $Flag, poll: ${PollSec}s)"

while ($true) {
    try {
        # ana Discord surec(ler)i: --type= icermeyen (yardimci degil) Discord.exe
        $mains = @(Get-CimInstance Win32_Process -Filter "Name='Discord.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' })
        if ($mains.Count -gt 0) {
            $bad = @($mains | Where-Object { $_.CommandLine -notmatch 'proxy-server' })
            if ($bad.Count -gt 0 -and ((Get-Date) - $lastFix).TotalSeconds -ge $CooldownSec) {
                Write-Log "proxy'siz Discord tespit edildi -> duzeltiliyor"
                $lastFix = Get-Date
                # 1) gelecekteki elle acmalar temiz olsun diye kisayollari tazele
                if (Test-Path $FixScript) {
                    try { & $FixScript -ProxyServer $Proxy -Quiet | Out-Null } catch { Write-Log "fix-discord hata: $($_.Exception.Message)" }
                }
                # 2) bozuk Discord'u kapat
                Get-Process Discord -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                # 3) proxy ile yeniden baslat
                if (Test-Path $UpdateExe) {
                    Start-Process -FilePath $UpdateExe -ArgumentList '--processStart', 'Discord.exe', '--process-start-args', "`"$Flag`""
                    Write-Log "Discord proxy ile yeniden baslatildi"
                } else {
                    Write-Log "Update.exe bulunamadi: $UpdateExe"
                }
                Start-Sleep -Seconds 8   # yeni surec otursun; ayni olayla tekrar tetiklenme
            }
        }
    } catch {
        Write-Log "dongu hatasi: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds $PollSec
}
