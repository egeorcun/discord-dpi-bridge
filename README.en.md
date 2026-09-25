# discord-dpi-bridge

**Read this in other languages:** [Türkçe](README.md) · **English**

**Can't reach Discord in your country?** This tool routes Discord past the block **without installing a kernel driver**. On Windows, anti-cheat games (ARC Raiders etc.) that refuse to start next to GoodbyeDPI work too. Runs on **Windows and macOS**.

| | 🪟 Windows | 🍎 macOS |
|---|---|---|
| Needs | Windows 10 (21H2+) / 11 | macOS 12+ (Intel or Apple Silicon) |
| Extra software | None | Xcode Command Line Tools (the installer asks for them) |
| Install | `install.ps1` | `macos/install.sh` |
| Check | `status.ps1` | `macos/status.sh` |
| Uninstall | `uninstall.ps1` | `macos/uninstall.sh` |

---

## 📥 Download

Grab the zip for your system from the **[Releases page](https://github.com/egeorcun/discord-dpi-bridge/releases/latest)** and extract it:

- 🪟 Windows → `discord-dpi-bridge-windows-vX.Y.Z.zip`
- 🍎 macOS → `discord-dpi-bridge-macos-vX.Y.Z.zip`

With git (both live in the same repo):

```bash
git clone https://github.com/egeorcun/discord-dpi-bridge
```

---

## 🪟 Windows

### 1) Install
Open the folder, **Shift + right-click an empty spot → "Open PowerShell window here"**, paste:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Approve the "Run as administrator" prompt. You can answer **Y** to every question.

### 2) When it finishes
- If the installer says **"restart"**, reboot.
- **Open Discord from the desktop shortcut.** Done. 🎉

It starts automatically at every boot from now on.

### Check / fix / uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1        # is it working? everything should be [OK]
powershell -ExecutionPolicy Bypass -File .\fix-discord.ps1   # if Discord stops opening one day (rarely needed, the guard fixes it itself)
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1     # revert everything
```

---

## 🍎 macOS

### 1) Install
Open Terminal, `cd` into the folder, run:

```bash
bash macos/install.sh
```

- If **Xcode Command Line Tools** are missing, macOS offers to install them. Run the command again afterwards.
- It asks for your password (network settings, `/etc/hosts` and the updater bridge). Do **not** prefix the command with `sudo`.
- At the end a **DNS profile** opens: **System Settings → General → Device Management** → "discord-dpi-bridge: DNS over HTTPS" → **Install**.

### 2) When it finishes
If Discord is open, **quit it completely** (Cmd+Q) and reopen it. Done. 🎉

It starts automatically at every login. No shortcut or flag needed; Discord updates can't break it. Still seeing "Update failed"? Check `bash macos/status.sh`.

### Check / uninstall

```bash
bash macos/status.sh      # is it working? everything should be [OK]
bash macos/uninstall.sh   # revert everything
```

> ⚠️ The macOS version has been tried on only a few real Macs. If something breaks, [open an issue](https://github.com/egeorcun/discord-dpi-bridge/issues) with the `status.sh` output. Details and options: **[macos/README.en.md](macos/README.en.md)**.

---

## 📱 Android?

This tool can't be ported to Android, but a ready-made app already does the job: **[ByeByeDPI](https://github.com/romanvht/ByeByeDPI)**. No root; in VPN mode you select only Discord, games are untouched. Paste the `byedpi.args` value from this repo's `config.json` into it. For DNS: Settings → Private DNS → `one.one.one.one`.

---

## How it works (briefly)

Tools like GoodbyeDPI bypass the block with a **kernel driver** (WinDivert); anti-cheats like Denuvo/EAC refuse to start the game when they see it. This tool does the same job **without a driver**, in user space. The core is the same on both systems: [ByeDPI](https://github.com/hufrea/byedpi), a local SOCKS5 proxy.

**Windows**
1. **ByeDPI** (`ciadpi.exe`) — the local proxy that bypasses the block.
2. **relay.ps1** — a bridge that also routes Discord's proxy-unaware updater through the proxy (via the hosts file).
3. **DNS over HTTPS** — gets past the ISP's DNS block.
4. **discord-guard** — repairs the setting automatically when a Discord update wipes it.

**macOS**
1. **ByeDPI** — built from source, runs as a LaunchAgent.
2. **PAC file** — a system proxy setting that sends only Discord domains to the proxy; the Discord app honours it, so no shortcut or guard is needed.
3. **relay.py** — Discord's updater ignores proxy/PAC settings, so its update domains are pointed at a local bridge via the hosts file and carried through ByeDPI.
4. **DNS over HTTPS profile** — gets past the ISP's DNS block.

Everything is reversible; the `uninstall` scripts restore the previous settings from a backup.

---

## Security & verification

- This repo ships **no executables.** On Windows, `ciadpi.exe` is downloaded during install from [ByeDPI's official release](https://github.com/hufrea/byedpi/releases); on macOS, ByeDPI is built on your Mac from its official source. Everything else is open, readable text.
- **If your antivirus says "PUA/Riskware":** ByeDPI is a circumvention tool, so some scanners flag it under that category; it is not a virus detection. If Windows Defender removes `ciadpi.exe`: Windows Security → Protection history → **"Allow on device"**, then run `install.ps1` again.
- Admin rights are requested only during install (hosts, DNS, proxy settings). On Windows nothing runs as admin afterwards; on macOS the updater bridge starts as root to open port 443 and immediately drops to the `nobody` user.

**VirusTotal (ByeDPI binary, v0.17.3):**
`ciadpi.exe` — SHA-256 `eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4`
→ https://www.virustotal.com/gui/file/eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4

<details>
<summary><b>SHA-256 of the source files (as obtained via git clone)</b></summary>

| File | SHA-256 |
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

Windows: `Get-FileHash .\file -Algorithm SHA256` · macOS: `shasum -a 256 macos/file`. Text-file hashes depend on line-ending settings; the most reliable check is `ciadpi.exe`.
</details>

## Limits — honestly

- This is a **workaround, not a permanent fix**; it may break if Discord changes its architecture.
- Voice chat (UDP) does not go through the proxy; usually fine, but it depends on the ISP.
- Defaults were verified on **Türk Telekom** (Windows). On another ISP or on macOS you may need to tune `byedpi.args` in `config.json` ([ByeDPI](https://github.com/hufrea/byedpi)).
- The legality of DPI circumvention varies by country; use at your own responsibility.

## Credits

- [ByeDPI](https://github.com/hufrea/byedpi) (hufrea) — all of the user-space DPI bypassing.
- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) (ValdikSS) — served for years.

## License

MIT. ByeDPI is licensed separately (MIT) and downloaded/built at install time.
