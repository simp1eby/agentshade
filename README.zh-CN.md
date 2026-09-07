<p align="center">
  <img src="assets/agentshade-icon.png" width="160" alt="AgentShade 图标">
</p>

<h1 align="center">AgentShade</h1>

<p align="center">屏幕暂暗，Agent 不停。</p>

<p align="center">简体中文 · <a href="README.md">English</a></p>

AgentShade 是一个轻量的原生 macOS 菜单栏工具。按下一个全局快捷键，即可用纯黑或自定义图片/GIF 遮住所有已连接屏幕，包括外接显示器；再按任意普通按键恢复桌面。

AgentShade 只创建全屏遮罩窗口，不会让 Mac 休眠、修改显示器硬件亮度，也不会停止终端、构建、下载、AI Agent 或其他正在运行的进程。

## 功能

- 使用 `Control + Option + Command + D` 遮住所有屏幕
- 按下任意普通按键恢复桌面
- 支持纯黑、PNG、JPEG、HEIC、WebP 和动态 GIF 遮罩
- 接入或移除显示器时自动适配
- 可选开机登录时启动
- 无需“辅助功能”权限
- 无统计、遥测、账号或网络服务

## 系统要求

- macOS 13 或更高版本
- 从源码构建需要 Swift 5.9 工具链或 Xcode Command Line Tools

## 构建与运行

```bash
git clone https://github.com/simp1eby/agentshade.git
cd agentshade
./scripts/package-app.sh
open outputs/AgentShade.app
```

打包结果位于 `outputs/AgentShade.app`。启用开机启动前，建议先将 App 移入 `/Applications`。

## 使用方法

1. 启动 AgentShade，菜单栏会出现半明半暗的圆形图标。
2. 按 `Control + Option + Command + D` 遮住全部屏幕。
3. 按任意普通按键恢复桌面；用于恢复的按键会被拦截，不会传给之前的应用。
4. 从菜单栏选择图片或 GIF，也可以随时恢复为纯黑。
5. 如需开机常驻，在菜单中启用“登录时启动”。macOS 若要求确认，请前往“系统设置 → 通用 → 登录项与扩展”允许 AgentShade。

鼠标点击不会退出遮罩。

## 隐私与安全

AgentShade 只会在当前用户的 Application Support 目录中保存你主动选择的遮罩图片。项目不包含 API 密钥、密码、统计 SDK 或网络请求。

本地构建使用临时签名。如需向其他用户公开分发二进制版本，应使用 Apple Developer ID 证书签名并完成公证。

## 开发检查

```bash
./scripts/run-checks.sh
```
