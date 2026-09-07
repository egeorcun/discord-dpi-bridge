<#
  discord-dpi-bridge relay (PowerShell surumu - Python GEREKTIRMEZ)

  Proxy desteklemeyen istemciler (Discord'un Rust guncelleyicisi) icin yerel
  TCP -> SOCKS5 koprusu. Hosts dosyasi hedef alan adini bir loopback IP'ye
  yonlendirir; bu betik o IP'yi dinler ve baglantiyi ByeDPI'nin SOCKS5 proxy'si
  uzerinden gercek sunucuya tasir. TLS'e dokunulmaz; sertifika dogrulamasi
  istemcide oldugu gibi kalir.

  Kritik ayrinti: hedef alan adi hosts'ta loopback'e cevrildigi icin SOCKS5'e
  alan adi VERILEMEZ (proxy de ayni DNS'i kullanip kendine geri baglanir).
  Gercek IP DoH ile cozulup SOCKS5'e IP olarak verilir. SNI TLS ClientHello
  icinde tasindigindan ByeDPI'nin DPI atlatmasi bundan etkilenmez.

  Yalnizca Windows'ta yerlesik gelen PowerShell 5.1 ve .NET ile calisir.
  Kullanim:  powershell -NoProfile -ExecutionPolicy Bypass -File relay.ps1 [config.json]
#>
param([string]$ConfigPath)
$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
$ConfigPath = (Resolve-Path $ConfigPath).Path
$cfg        = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$SocksHost  = $cfg.socks.host
$SocksPort  = [int]$cfg.socks.port
$DohUrl     = $cfg.doh.url
$DohTtl     = [int]$cfg.doh.ttl
$LogPath    = Join-Path (Split-Path -Parent $ConfigPath) 'relay.log'
$LogMax     = 5MB

$script:cache = @{}
$script:conns = New-Object System.Collections.ArrayList

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try {
        if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt $LogMax) {
            Move-Item $LogPath "$LogPath.old" -Force
        }
        Add-Content -Path $LogPath -Value $line -Encoding UTF8
    } catch { }
    try { [Console]::Out.WriteLine($line) } catch { }
}

function Resolve-RealIp([string]$hostname) {
    $hit = $script:cache[$hostname]
    if ($hit -and $hit.exp -gt (Get-Date)) { return $hit.ip }
    $ip = $null
    try {
        $r = Invoke-RestMethod -Uri ("{0}?name={1}&type=A" -f $DohUrl, $hostname) `
             -Headers @{ accept = 'application/dns-json' } -TimeoutSec 10
        foreach ($a in $r.Answer) {
            if ($a.type -eq 1) {
                $cand = [System.Net.IPAddress]::Parse($a.data)
                if (-not [System.Net.IPAddress]::IsLoopback($cand)) { $ip = $a.data; break }
            }
        }
        if ($ip) { Write-Log ("DoH: {0} -> {1}" -f $hostname, $ip) }
    } catch {
        Write-Log ("DoH basarisiz ({0}): {1}; sistem cozumleyicisi deneniyor" -f $hostname, $_.Exception.Message)
    }
    if (-not $ip) {
        foreach ($a in [System.Net.Dns]::GetHostAddresses($hostname)) {
            if ($a.AddressFamily -eq 'InterNetwork' -and -not [System.Net.IPAddress]::IsLoopback($a)) { $ip = $a.ToString(); break }
        }
    }
    if (-not $ip) { throw "$hostname icin loopback disinda A kaydi bulunamadi" }
    $script:cache[$hostname] = @{ ip = $ip; exp = (Get-Date).AddSeconds($DohTtl) }
    return $ip
}

function Read-Exact($stream, [int]$n) {
    $buf = New-Object byte[] $n
    $off = 0
    while ($off -lt $n) {
        $r = $stream.Read($buf, $off, $n - $off)
        if ($r -le 0) { throw "baglanti erken kapandi" }
        $off += $r
    }
    return $buf
}

function Connect-Socks([string]$ip, [int]$port) {
    $up = New-Object System.Net.Sockets.TcpClient
    $up.Connect($SocksHost, $SocksPort)
    $ns = $up.GetStream()
    # greeting: VER=5, 1 yontem, 0x00 (auth yok)
    $ns.Write([byte[]](5, 1, 0), 0, 3)
    $sel = Read-Exact $ns 2
    if ($sel[0] -ne 5 -or $sel[1] -ne 0) { $up.Close(); throw "SOCKS5 el sikisma reddedildi" }
    # connect: VER,CMD=1,RSV,ATYP=1(IPv4)+addr+port
    $addr = ([System.Net.IPAddress]::Parse($ip)).GetAddressBytes()
    $req  = [byte[]]@(5, 1, 0, 1) + $addr + @([byte](($port -shr 8) -band 0xFF), [byte]($port -band 0xFF))
    $ns.Write($req, 0, $req.Length)
    $rep = Read-Exact $ns 4
    if ($rep[1] -ne 0) { $up.Close(); throw ("SOCKS5 connect hata kodu {0}" -f $rep[1]) }
    switch ($rep[3]) {
        1 { [void](Read-Exact $ns 6) }                       # IPv4 + port
        4 { [void](Read-Exact $ns 18) }                      # IPv6 + port
        3 { $l = (Read-Exact $ns 1)[0]; [void](Read-Exact $ns ($l + 2)) }
    }
    return $up
}

function Start-Bridge($client, [string]$hostname, [int]$port) {
    $ip = Resolve-RealIp $hostname
    $up = Connect-Socks $ip $port
    $cs = $client.GetStream()
    $us = $up.GetStream()
    # cift yonlu pompalama .NET I/O thread'lerinde olur; PS thread'i bloke olmaz
    $t1 = $cs.CopyToAsync($us)
    $t2 = $us.CopyToAsync($cs)
    [void]$script:conns.Add([pscustomobject]@{ c = $client; u = $up; t1 = $t1; t2 = $t2 })
}

function Reap-Connections {
    for ($k = $script:conns.Count - 1; $k -ge 0; $k--) {
        $cn = $script:conns[$k]
        if ($cn.t1.IsCompleted -or $cn.t2.IsCompleted) {
            try { $cn.c.Close() } catch { }
            try { $cn.u.Close() } catch { }
            $script:conns.RemoveAt($k)
        }
    }
}

# ---- dinleyicileri ac ----
$routes = @($cfg.routes)
if ($routes.Count -eq 0) { Write-Log "[HATA] config.json icinde 'routes' bos"; exit 2 }
$listeners = @()
foreach ($r in $routes) {
    $lport = if ($r.listen_port) { [int]$r.listen_port } else { [int]$r.port }
    try {
        $L = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Parse($r.listen), $lport)
        $L.Start()
    } catch {
        Write-Log ("[HATA] {0}:{1} dinlenemiyor: {2}" -f $r.listen, $lport, $_.Exception.Message)
        continue
    }
    $listeners += [pscustomobject]@{ L = $L; host = $r.host; port = [int]$r.port; lip = $r.listen; lport = $lport }
    Write-Log ("[OK] {0}:{1} -> {2}:{3} (SOCKS5 {4}:{5})" -f $r.listen, $lport, $r.host, $r.port, $SocksHost, $SocksPort)
}
if ($listeners.Count -eq 0) { Write-Log "[HATA] hicbir dinleyici ayaga kalkmadi; cikiliyor"; exit 1 }

# ilk baglantida takilmamak icin hedefleri onceden coz
foreach ($x in $listeners) { try { [void](Resolve-RealIp $x.host) } catch { } }

# ---- kabul dongusu: tek thread, WaitAny ile 3 dinleyici + 1sn'lik reap zamanlayicisi ----
$acc = @($listeners | ForEach-Object { $_.L.AcceptTcpClientAsync() })
while ($true) {
    $delay = [System.Threading.Tasks.Task]::Delay(1000)
    $arr = [System.Threading.Tasks.Task[]]($acc + $delay)
    $i = [System.Threading.Tasks.Task]::WaitAny($arr)
    if ($i -lt $acc.Count) {
        try {
            $client = $acc[$i].Result
            Start-Bridge $client $listeners[$i].host $listeners[$i].port
        } catch {
            Write-Log ("[HATA] {0}:{1} -> {2}" -f $listeners[$i].host, $listeners[$i].port, $_.Exception.Message)
            try { $client.Close() } catch { }
        }
        $acc[$i] = $listeners[$i].L.AcceptTcpClientAsync()   # yeniden kur
    }
    Reap-Connections
}
