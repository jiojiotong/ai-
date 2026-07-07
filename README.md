# AI 构图相机

这是一个原生 iOS 原型项目，用于验证“AI 辅助实时构图拍照”的核心体验。

## 已实现

- 原生 SwiftUI App 入口。
- AVFoundation 实时相机预览。
- Apple Vision 端侧分析骨架，包括人脸、人体和显著主体检测。
- 构图规则引擎，包括主体位置、主体大小、贴边、上下留白、人像头顶留白、眼睛线和人物裁切提示。
- 取景器叠加层，包括三分线、主体框、人脸框和方向箭头。
- Hermes 当前画面分析接口。
- 实际取景动作指导：在取景器内显示移动方向、目标框和建议倍率。
- 前后摄切换。
- 点按对焦和曝光。
- 实时滤镜预览和拍照保存滤镜。
- AI 构图主流程：先识别当前取景，再给可执行动作建议，然后从滤镜库选择合适滤镜并自动套用。
- AI 滤镜推荐：Hermes 分析当前画面时会返回 `动作 + 滤镜 + 原因`，滤镜返回后实时预览和拍照保存都会使用该滤镜。
- Doka 风格多功能相机结构：AI 构图、拍照、人像、美颜、滤镜、背景和姿态模式，不包含登录、VIP 或分享入口。
- 滤镜分类面板：推荐、胶片、人像、风景、夜景、街拍、黑白和创意。
- 轻美颜/人像增强：自然、柔肤光泽、亮肤、奶油和暖肤，只调整色彩、亮度和柔和度，不做脸型或身体变形。
- 取景比例参考框和保存裁切，支持 FULL、1:1、3:4 和 9:16。
- 设置页，可配置 Hermes 模式、自动分析间隔、叠加层强度、API Key 和模型名。
- Hermes 相机大脑预设，可一键切换到服务器上的 `ai-camera-agent`。
- 手动 Hermes 分析和低频自动 Hermes 分析。

## 未实现或暂不包含

- 不包含拍后点评。
- 不包含自训练构图模型。
- 不包含登录、VIP/会员、分享入口或云相册。
- 背景模式当前不包含真实抠图、换背景或背景虚化模型，仅使用主体检测、构图提示和人像滤镜突出主体。
- 不支持逐帧 Hermes 分析。

## 滤镜

当前实现使用系统 CoreImage 管线提供实时滤镜预览和保存时滤镜处理，不依赖外部二进制库。初始滤镜包括：原图、鲜明、暖调胶片、日系淡彩、冷调街拍、经典黑白、复古、赛博霓虹、柔和人像、风景增强、清澈蓝调、纳什暖调、电影青橙、柯达金、富士绿、奶油、美食、夜景城市、暗调质感、空气感、高反差黑白、拍立得、反转片、褪色哑光、夏日、秋日、肤色光泽、160C、400H、Classic Chrome、Classic Neg、Vista 800、Superia 100 和 Superia 400。

GitHub 滤镜来源采用“源码可审计、license 清楚才拷贝”的策略。当前已按 MIT 许可改写 `Yummypets/YPImagePicker` 中的部分 CoreImage 滤镜配方，来源记录在 `AICompositionCamera/ThirdPartyFilters/LICENSES.md`。

## 打开方式

1. 安装完整 Xcode，不只是 Command Line Tools。
2. 打开 `AICompositionCamera.xcodeproj`。
3. 在项目 Signing & Capabilities 中设置自己的 Team。
4. 如需真机运行，把 `PRODUCT_BUNDLE_IDENTIFIER` 改成你账号下唯一的 Bundle ID。
5. 选择 iPhone 真机或模拟器运行。

相机预览需要真机才能完整验证。模拟器通常不能提供真实相机输入。

## Hermes 使用

1. 打开 App 后进入设置。
2. 填写 Hermes API Key。
3. 设置模型名，默认是 `ai-camera-agent`。
4. 选择 Hermes 模式：手动、自动、手动 + 自动或关闭。
5. 返回取景页后点击 `指导`，或启用自动模式让 App 在画面稳定时低频分析当前画面。
6. Hermes 返回后，取景页会先显示动作建议；如果识别出合适滤镜，App 会自动切换到 AI 推荐滤镜，并显示 `已套用` 和原因。

当前实现会把压缩后的当前取景帧发送到 Hermes 相机大脑，用于生成取景动作建议、变焦倍率和滤镜推荐。API Key 只保存在本机 Keychain，不写入源码。

## Hermes 相机大脑

服务器上已部署 `ai-camera-agent` Hermes profile，并通过相机大脑接口暴露：

- Base URL：`https://api.anyther.top/hermes-ai-camera/v1`
- Model：`ai-camera-agent`
- Health：`https://api.anyther.top/hermes-ai-camera/health`

在 App 设置页点击 `使用 Hermes 相机大脑` 会自动填入 Base URL 和模型名。Hermes API Key 不写入源码，需要在设置页 API Key 字段填写，App 会保存到本机 Keychain。

Hermes 返回格式需保持：

```text
动作：...
移动：left/right/up/down/closer/farther/hold
变焦：数字倍率
滤镜：filterId
原因：...
```

`filterId` 必须来自 App 内置滤镜列表，例如 `film400H`、`classicChromeAI`、`skinGlow` 或 `tealOrange`。App 收到已知滤镜 ID 后会自动套用到实时预览和拍照保存。

## 本机校验限制

当前开发环境只有 Command Line Tools，没有完整 Xcode 和 iOS SDK，因此这里无法执行 `xcodebuild`、无法编译 App、也无法导出 IPA。

已完成的静态校验：

- `AICompositionCamera/Info.plist` 通过 `plutil -lint`。
- `AICompositionCamera.xcodeproj/project.pbxproj` 通过 `plutil -lint`。
