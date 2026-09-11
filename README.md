<p align="center">
  <img src="assets/agentshade-icon.png" width="160" alt="AgentShade icon">
</p>

<h1 align="center">AgentShade</h1>

<p align="center"><strong>Shade your screens. Keep work running.</strong></p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

AgentShade is a lightweight, native macOS menu-bar utility for covering your displays without stopping the work behind them. Press one global shortcut for a black screen, a custom image or animated GIF, or a frosted-glass shade. An optional lid-angle mode deepens the frost as a supported Mac notebook closes.

AgentShade creates full-screen overlay windows. It does not change hardware brightness, pause terminals, stop builds or downloads, or put the Mac to sleep. Background processes normally continue while the shade is visible.

## Quick start

1. Launch AgentShade and open **Settings…** from its menu-bar icon.
2. Press `⌃⌥⌘D` to cover the selected displays. Press any regular key to restore them by default.
3. For automatic shading, open **Lid Gradient** and enable it if a readable sensor is detected. Manual and lid settings are independent.

## Highlights

- Shade all connected displays with the default shortcut `Control + Option + Command + D`.
- Choose solid black, a custom image / GIF, or a fixed frosted-glass artwork.
- Use separate display scopes for shortcut shading and lid-angle shading: all displays or built-in display only.
- Adapt the overlay when displays are connected, disconnected, or rearranged.
- Customize the global shortcut and optionally require that shortcut again to dismiss.
- Enable a smooth lid-angle frost curve on hardware with a readable sensor.
- Optionally blur a single in-memory desktop snapshot for enhanced lid frosting.
- Keep a permission-free built-in artwork fallback when access is not granted, unavailable, or capture fails.
- Switch the complete interface between Simplified Chinese and English without restarting.
- Start AgentShade at login through the standard macOS login-item service.

## Three focused settings areas

### 1. Shortcut Shade

Shortcut Shade controls the cover you invoke manually.

- **Scene:** Black, Image / GIF, or Frosted Glass. Black is the default.
- **Display scope:** All displays by default, or the built-in display only.
- **Global shortcut:** `⌃⌥⌘D` by default. A custom shortcut must include Command or Control plus a supported key.
- **Dismissal:** Any key by default. The restoring key is consumed instead of being sent to the previously focused app.
- **Shortcut-only dismissal:** Optional. When enabled, other keys are ignored and the configured shortcut restores the desktop.
- **Frost strength:** 50% by default. This adjusts the depth of the fixed blue material, not desktop transparency.
- **Custom media:** GIF, PNG, JPEG, HEIC, and WebP. Animated GIF playback is supported.

Mouse clicks do not dismiss the shade. The overlay absorbs pointer interaction until it is restored.

Manual Frosted Glass intentionally uses AgentShade's own fixed artwork. It does not capture, reveal, or blur the real desktop and does not require Screen Recording access.

### 2. Lid Gradient

Lid Gradient is optional and off by default. It becomes available only when AgentShade detects a readable lid-angle sensor at runtime.

- **Start angle:** 80° by default, adjustable from 41° to 95°.
- **Restore angle:** Always 5° above the selected start angle to avoid rapid retriggering.
- **Activation:** The angle must remain below the start angle for about 100 ms.
- **Curve:** Between your selected start angle and 40°, 30% of the closing travel reaches 65% strength. At 40° it reaches full strength.
- **Angle animation:** On by default. It can be disabled to use full configured strength immediately.
- **Blur radius:** 20 by default, adjustable from 0 to 60 when desktop-snapshot frosting is available. It does not change the permission-free artwork.
- **Display scope:** All displays by default, independently configurable from Shortcut Shade.
- **Enhanced frosting:** On by default; it uses a desktop snapshot only when Screen Recording access is available.

After a user dismisses an automatic shade, it stays suppressed for that lid cycle. Raise the display to the restore angle before lowering it to trigger again.

### 3. General

- Switch between English and Simplified Chinese immediately.
- Enable or disable Launch at Login.
- View Screen Recording status and use the visible permission button to request access or open the relevant System Settings page.

On first launch, a Chinese first preferred language selects Simplified Chinese; other languages select English. The saved in-app choice then takes precedence over later system-language changes.

The settings window has a fixed size. Losing focus or being partially covered does not close it. Sustained full coverage closes it and resumes lid automation, except while interacting with the Screen Recording prompt or System Settings. Returning from those screens preserves settings until the window is visible again.

## Requirements and compatibility

- macOS 13 or later.
- A Swift 5.9-compatible toolchain / Xcode Command Line Tools for source builds.
- Manual shading works without a lid-angle sensor.
- Automatic lid shading requires a readable Apple HID orientation sensor discovered at runtime.

The current implementation reads lid angles through HID and has not been validated against a complete MacBook model matrix. Compatibility is determined by detection on the current Mac. If the sensor is unavailable, AgentShade disables lid automation and keeps manual shading usable.

AgentShade is macOS-only; there is no Windows build. The package does not force a CPU architecture, and the packaging script builds for the active Swift toolchain and host target rather than producing a declared universal binary.

## Build and install from source

There is currently no prebuilt app attached to the project's existing GitHub release. Build the current app from source:

```bash
git clone https://github.com/simp1eby/agentshade.git
cd agentshade
./scripts/package-app.sh
open outputs
```

The script creates a release build at `outputs/AgentShade.app`. It reuses an installed certificate named `AgentShade Local Signing` when available; otherwise it uses ad-hoc signing. You can select an existing signing identity with `AGENTSHADE_SIGNING_IDENTITY`. The new bundle is signed and verified in a temporary folder before replacing the previous app; denied signing or failed verification leaves the previous app intact. macOS may require you to confirm access to the signing key in Keychain. Quit an existing AgentShade instance before rebuilding its app bundle.

The last command opens the output folder: move the app to `/Applications`, then launch it from there. Keep this location stable before granting permissions or enabling Launch at Login. A local signing certificate is not Apple Developer ID signing or notarization. Certificates and private keys are not part of this repository; never commit them.

If macOS requires approval for the login item, allow AgentShade in **System Settings → General → Login Items & Extensions**.

Future precompiled packages, if published, will appear on the [GitHub Releases page](https://github.com/simp1eby/agentshade/releases). Until then, the source build above is the supported installation path documented here.

## Screen Recording: optional and narrowly used

Black, custom media, manual Frosted Glass, and the built-in lid fallback need no Screen Recording access. AgentShade requests access only after you press the permission button in Settings.

With access available, enhanced **automatic lid shading** captures one complete frame for each selected display, excludes AgentShade's own windows, and applies blur and the shared blue material locally. Captures are held in memory, are not saved or uploaded, contain no audio or cursor, and are not continuous video recording. Captured pixels are released after dismissal.

Capture success and the macOS permission switch are treated as separate facts. If capture fails or is incomplete, AgentShade continues with its built-in gradient instead.

**Frosting can work without capture permission.** “Built-in frost ready” means the permission-free artwork is available, not that desktop capture is authorized. “Capture authorized” means the current app has access, while the visible explanation separately reports whether a frame has actually been verified or capture has failed. If you prefer the built-in effect, there is no need to grant access. These states are shown in both Lid Gradient and General; no tooltip is required to read them.

After granting access, quit and reopen the same AgentShade app. An ad-hoc rebuild can change the app's privacy identity, so an older grant may no longer match even when System Settings still displays an AgentShade entry. Keep the app at a stable path, restart that exact app, and use the Screen Recording button in Lid Gradient or General to reopen System Settings and confirm the current app entry.

AgentShade does not request Accessibility permission for its global shortcut or normal operation.

## What shading does—and does not do

- **Background work:** Terminals, local agents, builds, downloads, and other processes normally keep running because AgentShade only adds windows.
- **Focus:** Showing the shade activates AgentShade so it can receive and consume the restoring key. GUI automation or agents that depend on foreground keyboard or pointer input need separate compatibility testing.
- **Built-in-only behavior:** With ordinary-key dismissal, moving focus to an app on an uncovered external display dismisses the shade so it cannot become an unfocused trap. Manual shortcut-only dismissal intentionally keeps it up.
- **Sleep:** AgentShade does not install a keep-awake assertion or change macOS lid policy. Closing a notebook can still put the Mac to sleep, so a process being present after reopening does not prove it kept executing while closed.
- **Wake:** During display sleep, AgentShade pauses sensor reading and rendering while preserving the current cover. On wake it resumes detection when needed and refreshes an active shade, but it cannot guarantee control of the first system wake frame.
- **Privacy level:** Black is the opaque choice. Enhanced frost deliberately preserves some visual structure, especially near the start angle, and is not a screen lock. System lock screens remain the operating system's responsibility.

The app stays available as a menu-bar agent for its global shortcut, but this does not prevent system sleep or guarantee uninterrupted foreground automation.

## Local data and privacy

AgentShade stores the selected custom background in the current user's Application Support directory and saves local preferences such as scene, shortcut, language, display scopes, and lid settings. Lid-angle readings stay in memory.

The application source contains no account system, analytics SDK, telemetry pipeline, or network service. Screen snapshots used by enhanced lid frosting remain local and transient.

## Development checks

Useful focused checks include:

```bash
./scripts/run-checks.sh --default-blur
./scripts/run-checks.sh --lid-curve
./scripts/run-checks.sh --language-permissions
./scripts/run-checks.sh --permission-presentation
./scripts/run-checks.sh --permission-occlusion
./scripts/run-checks.sh --simple-lid
```

Checks that create AppKit windows, exercise real overlays, or read hardware require a logged-in graphical macOS session. For the optional integration and sensor path, run:

```bash
./scripts/run-checks.sh --integration --sensor
```

The integration and sensor option briefly exercises real overlays and HID readings; omit `--sensor` on hardware without a readable lid sensor. The language-permissions check uses a test permission provider and neither grants Screen Recording access nor captures the desktop.

## Current version

AgentShade `1.0.0`.
