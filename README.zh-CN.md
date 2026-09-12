<p align="center">
  <img src="assets/agentshade-icon.png" width="160" alt="AgentShade 图标">
</p>

<h1 align="center">AgentShade</h1>

<p align="center"><strong>屏幕暂暗，工作不停。</strong></p>

<p align="center"><a href="README.md">English</a> · 简体中文</p>

AgentShade 是一款轻量的 macOS 菜单栏工具：遮住屏幕，但不停止背后的工作。全局快捷键可以显示纯黑、自选图片/GIF 或内置毛玻璃；在支持的 Mac 笔记本上，合盖模式会随角度逐渐加深内置毛玻璃。

## 快速使用

1. 启动 AgentShade，点击菜单栏图标进入“设置…”。
2. 按 `⌃⌥⌘D` 遮住选定屏幕；默认按任意普通按键恢复。
3. 打开“合盖渐变”，在检测到可读取的开合角度传感器后启用自动遮罩。

## 主要亮点

- 覆盖所有已连接显示器，包括外接屏幕。
- 支持纯黑、自选图片/GIF 和内置毛玻璃。
- 快捷键遮罩与合盖遮罩可分别设置覆盖范围。
- 可自定义全局快捷键，也可要求再次按快捷键才能退出。
- 从起效角度到 40° 平滑渐变，合盖前 30% 行程达到 65% 强度。
- 中英文界面即时切换，无需重启。
- 可通过 macOS“登录项”设置开机启动。

## 设置分区

### 快捷键遮罩设置

- 场景：纯黑（默认）、图片/GIF 或毛玻璃。
- 覆盖屏幕：全部屏幕（默认）或仅内置屏幕。
- 快捷键：默认 `Control + Option + Command + D`；自定义组合必须包含 Command 或 Control。
- 退出方式：默认任意键，或仅允许已设置的快捷键退出。
- 毛玻璃强度：默认 50%，调整内置蓝色材质的深浅。
- 自选媒体：支持 GIF、PNG、JPEG、HEIC 和 WebP。

### 合盖渐变设置

- 默认关闭，检测到可用开合角度传感器后才能启用。
- 起效角度：默认 80°，可在 41°–95° 调整。
- 恢复角度：比起效角度高 5°，避免反复触发。
- 渐变曲线：合盖前 30% 行程达到 65% 强度，40° 达到最深。
- 模糊半径：默认 20，可用于调整内置毛玻璃渲染。
- 显示范围和动画可独立配置。

### 通用设置

- 一个按钮切换中文/英文。
- 开启或关闭登录时启动。

## 不需要屏幕录制权限

所有毛玻璃效果都使用 AgentShade 内置底图。应用不会采集、读取、保存或上传桌面，也不会打开“屏幕录制”权限弹窗，因此不同构建版本之间不会出现 TCC 或签名授权不匹配问题。

遮罩只是全屏窗口：不会修改硬件亮度、停止进程，也不会主动让 macOS 休眠。后台 Agent、终端、构建和下载通常会继续运行。

## 系统要求与兼容性

- macOS 13 或更高版本。
- 从源码构建需要兼容 Swift 5.9 的工具链。
- 手动快捷键遮罩不需要开合角度传感器。
- 只有检测到可读取的 Apple HID 开合角度传感器时才启用合盖自动遮罩。不支持的机型会禁用合盖设置，但手动功能仍可使用。

AgentShade 仅支持 macOS，打包会跟随当前 Swift 工具链和主机架构。

## 构建与安装

```bash
git clone https://github.com/simp1eby/agentshade.git
cd agentshade
./scripts/package-app.sh
open outputs
```

脚本会生成 `outputs/AgentShade.app`。本机有固定签名身份时会优先使用，否则使用 ad-hoc 签名。需要稳定路径时，可将 App 移到 `/Applications`；若系统提示，请在“系统设置 → 通用 → 登录项与扩展”允许 AgentShade。

证书、私钥、用户偏好和构建输出均不会提交到仓库。

## 开发检查

```bash
./scripts/run-checks.sh --no-capture-permission
./scripts/run-checks.sh --default-blur
./scripts/run-checks.sh --lid-curve
./scripts/run-checks.sh --language-permissions
./scripts/run-checks.sh --simple-lid
```

需要测试真实窗口时运行 `./scripts/run-checks.sh --integration`；只有具备可读开合角度传感器的设备才添加 `--sensor`。

## 当前版本

AgentShade `1.0.0`。
