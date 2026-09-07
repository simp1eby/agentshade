<p align="center">
  <img src="assets/agentshade-icon.png" width="160" alt="AgentShade icon">
</p>

<h1 align="center">AgentShade</h1>

<p align="center">Dark the screens. Keep your agents running.</p>

<p align="center"><a href="README.zh-CN.md">简体中文</a> · English</p>

AgentShade is a lightweight native macOS menu-bar utility. Press one global shortcut to cover every connected display—including external monitors—with solid black or a custom image/GIF. Press any regular key to return.

AgentShade only adds full-screen overlay windows. It does not sleep the Mac, change hardware brightness, or stop terminals, builds, downloads, AI agents, or other running processes.

## Features

- Covers all connected displays with `Control + Option + Command + D`
- Restores on the next regular key press
- Supports solid black, PNG, JPEG, HEIC, WebP, and animated GIF backgrounds
- Adapts when displays are connected or disconnected
- Optional launch at login
- No Accessibility permission required
- No analytics, telemetry, account, or network service

## Requirements

- macOS 13 or later
- Swift 5.9 toolchain / Xcode Command Line Tools for source builds

## Build and run

```bash
git clone https://github.com/simp1eby/agentshade.git
cd agentshade
./scripts/package-app.sh
open outputs/AgentShade.app
```

The packaged application is written to `outputs/AgentShade.app`. Move it to `/Applications` before enabling launch at login.

## Usage

1. Launch AgentShade and find the half-shaded circle in the menu bar.
2. Press `Control + Option + Command + D` to cover every display.
3. Press any regular key to restore the desktop. That key is consumed and is not forwarded to the previous application.
4. Use the menu-bar menu to select an image/GIF or return to solid black.
5. Enable **Launch at Login** from the menu if desired. macOS may ask you to approve it in **System Settings → General → Login Items & Extensions**.

Mouse clicks do not dismiss the shade.

## Privacy and security

AgentShade stores only the optional background image you choose, under the current user's Application Support directory. The project contains no API keys, passwords, analytics SDKs, or network requests.

Local builds are ad-hoc signed. Public binary distribution should use an Apple Developer ID certificate and notarization.

## Development checks

```bash
./scripts/run-checks.sh
```
