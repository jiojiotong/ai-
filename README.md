# AI 构图相机

这是一个原生 iOS 原型项目，用于验证“AI 辅助实时构图拍照”的核心体验。

## 已实现

- 原生 SwiftUI App 入口。
- AVFoundation 实时相机预览。
- Apple Vision 端侧分析骨架，包括人脸、人体和显著主体检测。
- 构图规则引擎，包括主体位置、主体大小、贴边、人像头顶留白和眼睛线提示。
- 取景器叠加层，包括三分线、主体框、人脸框和方向箭头。
- GPT 当前画面分析接口。
- 设置页，可配置 GPT 模式、自动分析间隔、叠加层强度、API Key 和模型名。
- 手动 GPT 分析和低频自动 GPT 分析。

## 未实现或暂不包含

- 不包含拍后点评。
- 不包含自训练构图模型。
- 不包含滤镜、美颜、修图、会员、登录或云相册。
- 不支持逐帧 GPT 分析。

## 打开方式

1. 安装完整 Xcode，不只是 Command Line Tools。
2. 打开 `AICompositionCamera.xcodeproj`。
3. 在项目 Signing & Capabilities 中设置自己的 Team。
4. 如需真机运行，把 `PRODUCT_BUNDLE_IDENTIFIER` 改成你账号下唯一的 Bundle ID。
5. 选择 iPhone 真机或模拟器运行。

相机预览需要真机才能完整验证。模拟器通常不能提供真实相机输入。

## GPT 使用

1. 打开 App 后进入设置。
2. 填写 OpenAI API Key。
3. 设置模型名，默认是 `gpt-4o`。
4. 选择 GPT 模式：手动、自动、手动 + 自动或关闭。
5. 返回取景页后点击 `AI 看一下`，或启用自动模式让 App 在画面稳定时低频分析当前画面。

当前实现会把压缩后的当前取景帧直接发送到 OpenAI API。生产版本应改成后端代理，避免在客户端保存或暴露 API Key。

## 本机校验限制

当前开发环境只有 Command Line Tools，没有完整 Xcode 和 iOS SDK，因此这里无法执行 `xcodebuild`、无法编译 App、也无法导出 IPA。

已完成的静态校验：

- `AICompositionCamera/Info.plist` 通过 `plutil -lint`。
- `AICompositionCamera.xcodeproj/project.pbxproj` 通过 `plutil -lint`。
