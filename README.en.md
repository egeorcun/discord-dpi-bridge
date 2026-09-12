# discord-dpi-bridge

**Read this in other languages:** [Türkçe](README.md) · **English**

**Can't reach Discord in your country, but anti-cheat games like ARC Raiders won't launch while GoodbyeDPI is on?** This tool fixes both at once: Discord works *and* the game works — because it installs no kernel driver, so anti-cheats stay happy.

---

## 🚀 How to run it (3 steps)

### 1) Download
Easiest: grab `discord-dpi-bridge-vX.X.X.zip` from the **[Releases page](https://github.com/egeorcun/discord-dpi-bridge/releases/latest)**, right-click → **Extract All**.

> With git: `git clone https://github.com/egeorcun/discord-dpi-bridge`

### 2) Install
Open the extracted folder. **Shift + right-click** an empty spot → **"Open PowerShell window here"**. Then paste this and press Enter:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

If a **"Yes / Run as administrator"** prompt appears, approve it. The installer does everything itself (it may ask a couple of questions — you can answer **Y** to all).

### 3) When it finishes
- If the installer says **"restart"**, reboot your PC.
- Then **open Discord from the desktop shortcut.** That's it. 🎉

From now on it runs automatically at every startup — you won't have to touch it again.

---

## ✅ Check that it works

Open PowerShell in the same folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\status.ps1
```

If everything shows **[OK]** and it says **"Her şey yolunda"** (all good) at the bottom, you're set.

## 🔧 If Discord stops opening one day

Usually you **won't need to** — the background guard fixes this automatically after Discord updates. But if it happens:

```powershell
powershell -ExecutionPolicy Bypass -File .\fix-discord.ps1
```

Then close and reopen Discord.

## 🗑️ Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Reverts everything it did (hosts, DNS, shortcuts, auto-start).

---

## Requirements

- **Windows 10 (21H2+) or Windows 11**
- **Nothing else** — no Python etc. Everything runs on the PowerShell that ships with Windows.
- One-time administrator prompt during install (for the hosts + DNS settings). Nothing runs as admin afterward.

## What it does and why (short version)

Tools like GoodbyeDPI beat the block with a **kernel driver** (`WinDivert`); anti-cheats like Denuvo/EAC refuse to run alongside it, so the game won't launch (ARC Raiders shows "0x1: Incorrect function"). This tool does the same job **without a driver**:

1. **ByeDPI** — a local proxy that beats the block in user space (no driver).
2. **relay.ps1** — a bridge that also routes Discord's updater through the proxy.
3. **DNS over HTTPS** — bypasses the ISP's DNS tampering.
4. **discord-guard** — auto-repairs when a Discord update breaks the setting.

If the installer finds GoodbyeDPI, it removes it (with your consent) — it doesn't delete the folder, just stops the Windows service.

---

## Security & verification

- This repo/download ships **no executable (.exe) files.** The only binary, `ciadpi.exe` (ByeDPI), is downloaded during install from [ByeDPI's official release](https://github.com/hufrea/byedpi/releases). Everything else is open, readable text.
- **If your antivirus says "PUA/Riskware":** ByeDPI is a censorship-circumvention tool, so some engines tag it with that category — it's not a malware detection. If Windows Defender removes `ciadpi.exe`: Windows Security → Protection history → **"Allow on device"**, then run `install.ps1` again.

**VirusTotal (ByeDPI binary, ByeDPI v0.17.3):**
`ciadpi.exe` — SHA-256 `eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4`
→ https://www.virustotal.com/gui/file/eb53ceeeb981cc6735ac24bb1e51e725280b86630e80fdf19ddc4ee4a5b54ef4

<details>
<summary><b>SHA-256 of source files (as obtained via git clone)</b></summary>

| File | SHA-256 |
|---|---|
| `relay.ps1` | `54d0f861842fcf18e03825a395056d486c46059c9bc6a17201004eb0e249ef98` |
| `discord-guard.ps1` | `91088481db498c9ade71406d690406920a0754a25a55059fa5ea6c5b8ab96c40` |
| `install.ps1` | `f3b2e4cc25bbe377c97e54b0efe6ef82f4ab1aabe5ca1661eb0b6a3ff6680575` |
| `uninstall.ps1` | `1d1f78ad7d9eb0e728b4e2e620df31d51f3fdb1e342643fb8e1fc5ae6e37e5aa` |
| `status.ps1` | `d1f535f6341e13805adbec4919fe8ecfc0ed53673c878348bb9cada9dbf4a703` |
| `fix-discord.ps1` | `2f195dbca2a222ff97e852f4069ab69f1f98e316f989fe587038bea9053c558e` |
| `config.json` | `43da260d90a56ff8886e94b5664774241d4d934f61a598db88f4365e31b37c5d` |

Verify with `Get-FileHash .\file -Algorithm SHA256`. Text-file hashes depend on line-ending settings; the most reliable check is `ciadpi.exe`, which is unaffected.
</details>

## Limits — honestly

- This is a **workaround, not a permanent fix**; it can break if Discord changes its internals (the guard catches most cases but isn't a guarantee).
- Voice (UDP) doesn't go through the proxy; usually fine, but may vary by ISP.
- The defaults were verified on **Türk Telekom**. On another ISP you may need to tune `byedpi.args` in `config.json` ([ByeDPI](https://github.com/hufrea/byedpi)).
- The legality of DPI circumvention varies by country; use is the user's responsibility.

## Credits

- [ByeDPI](https://github.com/hufrea/byedpi) (hufrea) — all of the user-space DPI bypass.
- [GoodbyeDPI](https://github.com/ValdikSS/GoodbyeDPI) (ValdikSS) — served us for years.

## License

MIT. ByeDPI is separately licensed (MIT) and downloaded during install.
