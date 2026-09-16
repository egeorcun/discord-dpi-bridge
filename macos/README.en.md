# discord-dpi-bridge — macOS

**Read this in other languages:** [Türkçe](README.md) · **English** · [Main README](../README.en.md)

Does what the Windows version does, on macOS: routes Discord past DPI blocking through [ByeDPI](https://github.com/hufrea/byedpi) running in user space, **with no kernel extension**. Only Discord domains go through the proxy; everything else is untouched.

> ⚠️ **Not yet verified on a real Mac.** The scripts were exercised end to end in a simulated macOS environment, but whether the ByeDPI parameters work on your ISP and whether Discord's updater honours the system proxy needs to be tried on your machine. If something breaks, [open an issue](https://github.com/egeorcun/discord-dpi-bridge/issues) with the `status.sh` output.

---

## 🚀 How to run it (3 steps)

### 1) Download
```bash
git clone https://github.com/egeorcun/discord-dpi-bridge
cd discord-dpi-bridge
```
(or download `discord-dpi-bridge-macos-vX.Y.Z.zip` from [Releases](https://github.com/egeorcun/discord-dpi-bridge/releases/latest), extract it and `cd` into it in Terminal.)

### 2) Install
```bash
bash macos/install.sh
```
- If **Xcode Command Line Tools** are missing, the installer asks macOS to install them (one time, from Apple). Run the script again afterwards.
- It asks for your password **once** for network settings (`sudo`). Do not run the script itself with `sudo`.
- At the end a **DNS over HTTPS profile** opens. macOS does not allow installing profiles from the command line; go to **System Settings → General → Device Management** (older versions: Privacy & Security → Profiles), pick "discord-dpi-bridge: DNS over HTTPS" → **Install**.

### 3) When it finishes
If Discord is open, **quit it completely** (Cmd+Q, and Quit from the menu-bar icon) and reopen it. That's it.

It starts automatically at every login from now on. Discord needs no shortcut or flag; it uses the system proxy setting, so Discord updates cannot break it.

---

## ✅ Check that it works
```bash
bash macos/status.sh
```
All **[OK]** and "Her şey yolunda" (all good) at the bottom means you're set. `--no-network` skips the tests that need internet.

## 🗑️ Uninstall
```bash
bash macos/uninstall.sh
```
Reverts everything: LaunchAgents, system proxy, DNS (from backup), the DoH profile, the install folder. `--keep-dns` keeps the DNS/DoH setting.

---

## Requirements
- **macOS 12 (Monterey) or newer**, Intel or Apple Silicon.
- **Xcode Command Line Tools** (`xcode-select --install`). ByeDPI has no official macOS binary, so it is built from source; the compiler, `git` and `python3` come from here. **Nothing else** is needed (no Homebrew).

## What it does and why (briefly)
On macOS both Discord (Electron) and its updater **honour the system proxy setting**, so the hosts/relay/shortcut/guard pieces of the Windows version are not needed:

1. **ByeDPI** is built from source and runs as a user-level **LaunchAgent** (SOCKS5 on `127.0.0.1:1080`).
2. A **PAC file** that sends only Discord domains to that proxy is generated and served from `127.0.0.1:18080` (Chromium does not accept `file://` PAC URLs).
3. `networksetup` points every network service (Wi-Fi, Ethernet) at that PAC as its **automatic proxy configuration**.
4. DNS is set to Cloudflare and a **DNS over HTTPS profile** is generated (for ISPs that hijack plain DNS).

Install folder: `~/Library/Application Support/discord-dpi-bridge/` (ByeDPI, PAC, logs, network-settings backup).

## Options
| `install.sh` | |
|---|---|
| `-y` | Don't ask anything (doesn't wait for Enter after the profile step) |
| `--dry-run` | Change nothing, just describe |
| `--skip-dns` / `--skip-proxy` | Skip that step |
| `--system-socks` | Set a **system-wide SOCKS** proxy instead of the PAC. Fallback if Discord's updater ignores the PAC; every app that honours the system proxy then goes through ByeDPI (thanks to `--auto=torst`, unblocked traffic passes through untouched). |
| `--byedpi-tag vX.Y.Z` | Pin a ByeDPI version (default: latest) |

The `macos` section of `config.json` lets you change the proxied domains (`proxy_domains`), the PAC port and macOS-specific ByeDPI parameters (`byedpi_args`, falls back to `byedpi.args` when empty); re-run `install.sh` afterwards.

## Troubleshooting
- **`status.sh` shows "discord.com (SOCKS5 uzerinden)" as an error:** the ByeDPI parameters don't fit your ISP. Adjust `config.json → byedpi.args` per the [ByeDPI README](https://github.com/hufrea/byedpi) (`--disorder` may behave differently on macOS than on Windows; start with `--split 1 --disorder 1 --auto=torst --tlsrec 1+s`), then `bash macos/install.sh -y`.
- **Discord stuck in an "update failed" loop:** the updater may not be using the PAC → `bash macos/install.sh -y --system-socks`.
- **DoH profile won't install:** `open ~/Library/Application\ Support/discord-dpi-bridge/discord-dpi-bridge-doh.mobileconfig` and install it from System Settings.
- Logs: `~/Library/Application Support/discord-dpi-bridge/logs/`.

## Security
- This folder ships **no executables**; ByeDPI is cloned from its [official source](https://github.com/hufrea/byedpi) and built on your Mac (tag recorded in `byedpi/version.txt`).
- Nothing runs as root. `sudo` is used only for `networksetup` (proxy/DNS settings).
- The PAC server listens on `127.0.0.1` only and returns nothing but `proxy.pac`.

<details>
<summary><b>SHA-256 of the source files</b></summary>

| File | SHA-256 |
|---|---|
| `install.sh` | `b00f5378f9be1d9b83dc4d47fac06957168cdf3bf3774e1a345fd34c47b4b29e` |
| `uninstall.sh` | `ad33dda1d1d73622bd9d621c892a5d1e4d3b1ea4c64a06b8074c2c95255082a4` |
| `status.sh` | `376e64a0148d309e6a85348acb9cba75019c07bfb1e8ca1759b37a0974ff3b9d` |
| `lib.sh` | `c01577ff6dafad61c06a27df8d6e6b96f99c4a7e4bb0cb663be2ad2cd06e05a3` |
| `pac-server.py` | `76fe793c7ebfaf3bffcfc53c7032c0866695f95d9c53ddd91280163cb662a57f` |

Verify with `shasum -a 256 macos/<file>`.
</details>

## Limits — honestly
- Every limit of the Windows version applies: a workaround, not a permanent fix; may break if Discord changes its architecture; voice (UDP) does not go through the proxy.
- The default ByeDPI parameters were verified on **Türk Telekom on Windows**; whether the same parameters work on macOS still needs testing.
- The DoH profile step needs user confirmation; a fully silent install is not possible.
