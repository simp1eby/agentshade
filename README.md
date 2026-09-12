<p align="center">
  <img src="assets/agentshade-icon.png" width="160" alt="AgentShade icon">
</p>

<h1 align="center">AgentShade</h1>

<p align="center"><strong>Shade your screens. Keep work running.</strong></p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

AgentShade is a lightweight macOS menu-bar utility that covers displays while work continues behind the overlay. A global shortcut can show a black shade, custom image/GIF, or frosted artwork. On supported Mac notebooks, the lid-angle mode gradually deepens the built-in frost as the lid closes.

## Quick start

1. Launch AgentShade and choose **Settings…** from the menu-bar icon.
2. Press `⌃⌥⌘D` to cover the selected displays. Press any regular key to restore them by default.
3. Open **Lid Gradient** to enable automatic shading when a readable lid-angle sensor is available.

## Highlights

- Cover all connected displays, including external monitors.
- Choose black, a custom image/GIF, or the built-in frosted artwork.
- Configure shortcut and lid display scopes independently.
- Customize the global shortcut and optionally require that shortcut to dismiss.
- Smoothly animate lid frosting from the configured start angle down to 40°.
- Switch the interface between Simplified Chinese and English without restarting.
- Optionally start AgentShade at login through macOS Login Items.

## Settings

### Shortcut Shade

- Scene: Black (default), Image/GIF, or Frosted Glass.
- Display scope: All displays (default) or the built-in display only.
- Shortcut: `Control + Option + Command + D` by default; custom shortcuts must include Command or Control.
- Dismissal: Any key by default, or the configured shortcut only.
- Frost strength: 50% by default, controlling the built-in blue material depth.
- Custom media: GIF, PNG, JPEG, HEIC, and WebP.

### Lid Gradient

- Optional and disabled by default.
- Start angle: 80° by default, configurable from 41° to 95°.
- Restore angle: five degrees above the start angle to prevent repeated triggers.
- Curve: the first 30% of closing travel reaches 65% strength; 40° reaches maximum strength.
- Blur radius: 20 by default, configurable for the local artwork renderer.
- Display scope and animation can be configured independently from Shortcut Shade.

### General

- Toggle English/Chinese with one button.
- Enable or disable Launch at Login.

## No Screen Recording permission required

All user-facing frosting uses AgentShade’s bundled artwork. The app never captures, reads, stores, or uploads the desktop, and it never opens a Screen Recording permission prompt. This keeps the visual behavior consistent and avoids TCC/signing issues across rebuilds.

The overlay is a normal full-screen window: it does not change hardware brightness, stop processes, or intentionally put macOS to sleep. Background agents, terminals, builds, and downloads normally continue running.

## Requirements and compatibility

- macOS 13 or later.
- Swift 5.9-compatible toolchain for source builds.
- Manual shortcut shading works without a lid sensor.
- Lid automation is enabled only when a readable Apple HID lid-angle sensor is detected. Unsupported hardware keeps the manual features available and disables the lid controls.

AgentShade is macOS-only. The package follows the active Swift toolchain and host architecture.

## Build and install

```bash
git clone https://github.com/simp1eby/agentshade.git
cd agentshade
./scripts/package-app.sh
open outputs
```

The script creates `outputs/AgentShade.app`. It uses the local signing identity when available and otherwise falls back to ad-hoc signing. Move the app to `/Applications` if you want a stable launch location, then allow it in **System Settings → General → Login Items & Extensions** when macOS asks.

Certificates, private keys, user preferences, and build outputs are intentionally excluded from this repository.

## Development checks

```bash
./scripts/run-checks.sh --no-capture-permission
./scripts/run-checks.sh --default-blur
./scripts/run-checks.sh --lid-curve
./scripts/run-checks.sh --language-permissions
./scripts/run-checks.sh --simple-lid
```

For the optional integration path, use `./scripts/run-checks.sh --integration`; add `--sensor` only on hardware with a readable lid sensor.

## Current version

AgentShade `1.0.0`.
