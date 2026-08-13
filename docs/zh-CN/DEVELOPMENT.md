# 轻截开发与维护

## 环境与结构

需要 Apple Silicon Mac、macOS 15+ 和 Xcode Command Line Tools。`QuickMarkShot.swift` 负责截图、标注、菜单和快捷键；`Recording.swift` 负责 ScreenCaptureKit 来源与录制；`MouseZoom.swift` 负责录制后的鼠标跟随合成；`main.swift` 为入口。

## 构建、安装与验证

```sh
git clone https://github.com/lexaup/QuickMarkShot.git
cd QuickMarkShot
./build.sh
./install.sh
./Scripts/verify.sh
```

构建输出为 `build/轻截-macOS.zip`，采用临时签名。自动验证只覆盖编译、归档、plist、版本、arm64、签名、图标及源码契约，不会申请 TCC 权限，也不代表截图、声音、窗口选择已做交互测试。

## 维护规则

- 捕获相关修改必须人工回归截图和四类录屏来源。
- 用户可见修改同步中文、英文文档和 CHANGELOG。
- 不提交构建包、录屏、私人截图或其他捕获内容。
- 递增 `Info.plist` 中营销版本和 Build。

## 发版

先运行验证脚本，再完成[发版清单](RELEASE_CHECKLIST.md)的人工权限和捕获测试。创建带注释标签，构建 ZIP、记录 SHA-256，上传 Release 后从公开页面下载核验。
