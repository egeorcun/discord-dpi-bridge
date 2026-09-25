# discord-dpi-bridge — macOS

**Read this in other languages:** [Türkçe](README.md) · **English** · [Main README](../README.en.md)

Does what the Windows version does, on macOS: routes Discord past DPI blocking through [ByeDPI](https://github.com/hufrea/byedpi) running in user space, **with no kernel extension**. Only Discord domains go through the proxy; everything else is untouched.

> ⚠️ Tried on only a few real Macs so far. Whether the ByeDPI parameters work on your ISP needs to be tried on your machine. If something breaks, [open an issue](https://github.com/egeorcun/discord-dpi-bridge/issues) with the `status.sh` output.

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
- It asks for your password for network settings, `/etc/hosts` and the updater bridge (`sudo`). Do not run the script itself with `sudo`.
- At the end a **DNS over HTTPS profile** opens. macOS does not allow installing profiles from the command line; go to **System Settings → General → Device Management** (older versions: Privacy & Security → Profiles), pick "discord-dpi-bridge: DNS over HTTPS" → **Install**.

### 3) When it finishes
If Discord is open, **quit it completely** (Cmd+Q, and Quit from the menu-bar icon) and reopen it. That's it.

It starts automatically at every login from now on. Discord needs no shortcut or flag; the app uses the system proxy setting and its updater uses the bridge, so Discord updates cannot break it.

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
Reverts everything: LaunchAgents, the updater bridge and its `/etc/hosts` entries, system proxy, DNS (from backup), the DoH profile, the install folder. `--keep-dns` keeps the DNS/DoH setting.

---

## Requirements
- **macOS 12 (Monterey) or newer**, Intel or Apple Silicon.
- **Xcode Command Line Tools** (`xcode-select --install`). ByeDPI has no official macOS binary, so it is built from source; the compiler, `git` and `python3` come from here. **Nothing else** is needed (no Homebrew).

## What it does and why (briefly)
On macOS Discord (Electron) **honours the system proxy setting**, so the shortcut/guard pieces of the Windows version are not needed. Discord's **updater** (Rust), however, ignores proxy/PAC settings, so the Windows hosts + bridge approach is used for it:

1. **ByeDPI** is built from source (through launchd, to avoid Gatekeeper's provenance block) and runs as a user-level **LaunchAgent** (SOCKS5 on `127.0.0.1:1080`).
2. A **PAC file** that sends only Discord domains to that proxy is generated and served from `127.0.0.1:18080` (Chromium does not accept `file://` PAC URLs).
3. `networksetup` points every network service (Wi-Fi, Ethernet) at that PAC as its **automatic proxy configuration**.
4. **Updater bridge:** `updates.discord.com`, `stable.dl2.discordapp.net` and `dl.discordapp.net` are pointed at `127.0.0.1` in `/etc/hosts`. `relay.py` runs as a **LaunchDaemon** on `127.0.0.1:443`, reads the domain from the TLS handshake (SNI) and carries only those domains to the real server through ByeDPI. TLS is not touched; certificate validation stays in Discord.
5. DNS is set to Cloudflare and a **DNS over HTTPS profile** is generated (for ISPs that hijack plain DNS).

Install folder: `~/Library/Application Support/discord-dpi-bridge/` (ByeDPI, PAC, logs, network-settings backup).

## Options
| `install.sh` | |
|---|---|
| `-y` | Don't ask anything (doesn't wait for Enter after the profile step) |
| `--dry-run` | Change nothing, just describe |
| `--skip-dns` / `--skip-proxy` / `--skip-relay` | Skip that step |
| `--system-socks` | Set a **system-wide SOCKS** proxy instead of the PAC; every app that honours the system proxy then goes through ByeDPI (thanks to `--auto=torst`, unblocked traffic passes through untouched). |
| `--byedpi-tag vX.Y.Z` | Pin a ByeDPI version (default: latest) |

The `macos` section of `config.json` lets you change the proxied domains (`proxy_domains`), the updater domains carried by the bridge (`relay_hosts`), the PAC port and macOS-specific ByeDPI parameters (`byedpi_args`, falls back to `byedpi.args` when empty); re-run `install.sh` afterwards.

## Troubleshooting
- **ByeDPI never runs (port 1080 not listening, empty `byedpi.log`):** macOS 26 stamps executables produced by a downloaded app (Warp, iTerm, VSCode, Claude Code…) with a "provenance" mark, and the kernel kills them instantly (`ASP: Security policy would not allow process`). `install.sh` therefore builds through launchd, where the mark is never applied. A broken binary left over from an older install is not rebuilt automatically: run `echo v0.0.0 > "$HOME/Library/Application Support/discord-dpi-bridge/byedpi/version.txt"` first, then install again.
- **`status.sh` reports a "discord.com (via SOCKS5)" error:** the ByeDPI parameters don't fit your ISP. Adjust `config.json → byedpi.args` per the [ByeDPI README](https://github.com/hufrea/byedpi) (`--disorder` may behave differently on macOS than on Windows; start with `--split 1 --disorder 1 --auto=torst --tlsrec 1+s`), then `bash macos/install.sh -y`.
- **Discord stuck in an "Update failed — retrying" loop:** check the "updater bridge" and "update server (via relay)" rows in `status.sh`; if any fail, run `bash macos/install.sh -y`. Bridge log: `~/Library/Application Support/discord-dpi-bridge/logs/relay.log`. The updater's own log: `~/Library/Application Support/discord/logs/Discord_updater_rCURRENT.log` (if it contacts a new domain, add it to `config.json → macos.relay_hosts`).
- **DoH profile won't install:** `open ~/Library/Application\ Support/discord-dpi-bridge/discord-dpi-bridge-doh.mobileconfig` and install it from System Settings.
- Logs: `~/Library/Application Support/discord-dpi-bridge/logs/`.

## Security
- This folder ships **no executables**; ByeDPI is cloned from its [official source](https://github.com/hufrea/byedpi) and built on your Mac (tag recorded in `byedpi/version.txt`).
- `sudo` is used only for `networksetup` (proxy/DNS), `/etc/hosts` and installing the bridge. The bridge starts as root to open port 443 and drops to the `nobody` user right after. Its script lives under `/Library/Application Support/discord-dpi-bridge/`, owned by root (users cannot modify it).
- The bridge listens only on `127.0.0.1`/`::1` and carries only the domains in `relay_hosts`; any other SNI is closed.
- The PAC server listens on `127.0.0.1` only and returns nothing but `proxy.pac`.

<details>
<summary><b>SHA-256 of the source files</b></summary>

| File | SHA-256 |
|---|---|
| `install.sh` | `278eaf0338421428d398649435725ea38066f8e2d92234265b967cc88aa266dc` |
| `uninstall.sh` | `0d4179c5fe61640ee31b74c5d5471864a49bff9545e70301b5c2c6cab0c2e2c7` |
| `status.sh` | `bfcbee809bdde54282bbf46d04a18822dc9b72bba7463c8e91e724e696eeed80` |
| `lib.sh` | `6770e354f2440755e8fe9568405ff8377ebb13a6447631d49a9fb4e472879dee` |
| `pac-server.py` | `360ec0a25f67f8361cdc90853c1be485a5e554b6a15c840faf65d21c3fe7f41f` |
| `relay.py` | `6a75f3e93abb84c7192bcf1ff4e319fcf3cb66088a797c0bd7eb19b67e45debc` |

Verify with `shasum -a 256 macos/<file>`.
</details>

## Limits — honestly
- Every limit of the Windows version applies: a workaround, not a permanent fix; may break if Discord changes its architecture; voice (UDP) does not go through the proxy.
- The default ByeDPI parameters were verified on **Türk Telekom on Windows**; whether the same parameters work on macOS still needs testing.
- The DoH profile step needs user confirmation; a fully silent install is not possible.
