# GitHub 自动打包 IPA

本项目包含 GitHub Actions workflow：

- 文件：`.github/workflows/ios-signed-ipa.yml`
- 名称：`iOS Signed IPA`
- 触发方式：推送到 `main` 或手动 `workflow_dispatch`
- 输出：`AICompositionCamera-signed-device.ipa`

## 需要准备的 Apple 签名材料

要生成能安装到 iPhone 的 IPA，GitHub Actions 必须拿到签名证书和描述文件。

需要三个 GitHub Secrets：

- `IOS_CERTIFICATE_P12_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_PROVISION_PROFILE_BASE64`

## 证书要求

如果你想通过链接/文件安装到指定设备，推荐使用：

- Apple Development 证书 + development profile，用于开发调试。
- Apple Distribution 证书 + Ad Hoc profile，用于分发到已登记 UDID 的设备。

workflow 默认使用 `ad-hoc` export method。手动运行 workflow 时可以选择：

- `ad-hoc`
- `development`
- `app-store`

## 生成 base64 secrets

在 macOS 上准备好 `.p12` 证书和 `.mobileprovision` 描述文件后执行：

```bash
base64 -i certificate.p12 | pbcopy
```

把剪贴板内容保存到 GitHub Secret：`IOS_CERTIFICATE_P12_BASE64`。

```bash
base64 -i profile.mobileprovision | pbcopy
```

把剪贴板内容保存到 GitHub Secret：`IOS_PROVISION_PROFILE_BASE64`。

`.p12` 导出时设置的密码保存到：`IOS_CERTIFICATE_PASSWORD`。

## GitHub 设置位置

进入 GitHub 仓库：

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

逐个添加三个 secret。

也可以使用项目里的脚本自动设置，避免把 base64 内容打印到终端：

```bash
scripts/set-github-ios-secrets.sh OWNER/REPO
```

其中 `OWNER/REPO` 替换成你的 GitHub 仓库，例如：

```bash
scripts/set-github-ios-secrets.sh jiojiotong/ai-camera
```

脚本会隐藏输入证书密码，避免密码出现在 shell 历史记录中。也可以用环境变量：

```bash
IOS_CERTIFICATE_PASSWORD=你的密码 scripts/set-github-ios-secrets.sh jiojiotong/ai-camera
```

脚本会读取：

```text
/Volumes/其他/Workspace/证书/证书文件(2).p12
/Volumes/其他/Workspace/证书/描述文件(1).mobileprovision
```

并写入 workflow 需要的三个 GitHub Secrets。

## Bundle ID

workflow 会从 `.mobileprovision` 里读取 Bundle ID，并在 `xcodebuild archive` 时覆盖项目里的 `PRODUCT_BUNDLE_IDENTIFIER`。

因此描述文件里的 App ID 必须匹配你要签名的 App，例如：

```text
com.yourname.AICompositionCamera
```

## 产物位置

workflow 成功后，在 GitHub Actions run 页面下载 artifact：

- `AICompositionCamera-signed-ipa`

手动运行 workflow 时，还会创建 GitHub Release：

- tag 格式：`ios-signed-<run_number>`
- 包含 `.ipa` 和 `.app.zip`

## 常见失败原因

- GitHub Secrets 没设置或 base64 内容复制不完整。
- `.p12` 密码不正确。
- 描述文件类型和 export method 不一致。
- 描述文件没有包含目标 iPhone 的 UDID。
- Bundle ID 和描述文件不匹配。
- Apple 证书过期或被撤销。

## 当前环境限制

本地机器没有完整 Xcode 和 iOS SDK，所以无法在本地验证 `xcodebuild archive`。workflow 会在 GitHub 的 `macos-14` runner 上使用 Xcode 15.4 构建。
