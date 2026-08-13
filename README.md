# 轻截 / QuickMarkShot

[English](README.en.md) · [中文使用手册](docs/zh-CN/USER_GUIDE.md) · [开发维护](docs/zh-CN/DEVELOPMENT.md) · [常见问题](docs/zh-CN/TROUBLESHOOTING.md)

## 软件简介

轻截是一款原生、轻量的 macOS 截图、快速标注和录屏工具。它常驻状态栏，使用系统框架在本机完成捕获、标注、编码和鼠标跟随放大处理。

## 功能

- `⌘⇧1` 主屏幕截图，`⌘⇧2` 区域或窗口截图
- 截图后直接用矩形、圆形、箭头、画笔标注
- 自定义颜色和线宽，Shift 约束正方形/正圆，撤销、重做、清除、复制、保存 PNG
- 打开已有图片继续标注
- `⌘⇧5` 录制整个显示器、区域、窗口或应用
- 可选系统声音、鼠标指针和点击提示
- 1.5×、1.8×、2.0× 鼠标跟随放大，停止后本地合成
- MP4（H.264 + AAC）保存到 `~/Movies/轻截录屏`
- `⌘⇧0` 隐藏或恢复状态栏图标

## 软件优点

- AppKit、ScreenCaptureKit、AVFoundation 等原生框架，无第三方运行时
- 捕获与处理均在本机完成，不上传截图或录屏
- 截图保持源分辨率，截图到标注流程短
- 录制来源可明确选择，权限状态有清晰提示
- 单一菜单栏入口，同时覆盖截图、标注和录屏

## 系统要求与权限

- macOS 15.0 或更高版本
- Apple Silicon（arm64）
- 截图和录屏需要“屏幕与系统录音”权限；系统声音采集也由该系统权限管理

## 安装

从 [Releases](https://github.com/lexaup/QuickMarkShot/releases) 下载 `QuickMarkShot-macOS.zip`，解压并将 `轻截.app` 移入“应用程序”。首次启动被拦截时，在“系统设置 → 隐私与安全性”确认打开；首次捕获时按提示授权并重启应用。

## 快捷键

| 操作 | 快捷键 |
|---|---|
| 主屏幕截图 | `⌘⇧1` |
| 区域/窗口截图 | `⌘⇧2` |
| 开始录屏 | `⌘⇧5` |
| 隐藏/恢复状态栏图标 | `⌘⇧0` |

完整标注快捷键和操作步骤见[中文使用手册](docs/zh-CN/USER_GUIDE.md)。

## 隐私

轻截不上传捕获内容、不包含遥测；截图、录屏及鼠标放大后处理均在本机完成。录屏文件默认保存在用户的“影片”目录。

## 构建

```sh
git clone https://github.com/lexaup/QuickMarkShot.git
cd QuickMarkShot
./Scripts/verify.sh
```

输出 ZIP 位于 `build/轻截-macOS.zip`。详见[开发维护手册](docs/zh-CN/DEVELOPMENT.md)。

## 版本历史

源码历史包含 v1.0、v2.0 Build 2/3、v2.1 Build 4/5。仅最终 v2.1 Build 5 的原始安装包被保留并附在 Release；其余版本不伪造历史二进制。详见 [CHANGELOG](CHANGELOG.md)。

## 参与维护

欢迎提交 Issue 和 Pull Request。请阅读 [CONTRIBUTING](CONTRIBUTING.md)，安全问题见 [SECURITY](SECURITY.md)。

## 许可证

[MIT](LICENSE)
