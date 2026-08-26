# iOS 私密云端签名

清序保留公开源码和公开的未签名 IPA；包含证书和设备授权信息的签名版仅通过 `Private Signed iOS` 工作流生成。

公开仓库的 Actions Artifact 对仓库读者可见，因此工作流不会上传原始签名 IPA，而是上传使用 AES-256 和文件名加密的 `.7z`。压缩包仅保留 1 天，也不会进入 GitHub Release。

## Apple 标识

- 主应用 App ID：`one.darker.qingxu`
- Widget/Live Activity 扩展 App ID：`one.darker.qingxu.widgets`
- App Group：`group.one.darker.qingxu`

主应用和扩展必须属于同一个 Apple Developer Team。两份描述文件都必须授权上面的 App Group，并包含需要安装设备的 UDID。

## GitHub 环境 Secrets

在仓库的 `Settings -> Environments` 中创建 `ios-signing` 环境，然后添加：

环境 Secrets 只能供引用该环境的 Actions 作业使用，但拥有仓库写入权限的人仍可修改工作流来调用它们。因此不要给不可信账号仓库写入权限。

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | Apple Distribution `.p12` 的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `IOS_MAIN_PROFILE_BASE64` | 主应用 `.mobileprovision` 的 Base64 |
| `IOS_WIDGET_PROFILE_BASE64` | Widget 扩展 `.mobileprovision` 的 Base64 |
| `IOS_SIGNED_ARCHIVE_PASSWORD` | 至少 16 位的私密压缩包密码 |

PowerShell 可使用以下方式写入二进制 Secret，命令不会把文件提交进 Git：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('主应用.mobileprovision')) |
  gh secret set IOS_MAIN_PROFILE_BASE64 --env ios-signing --repo FelixZoe/qingxu

[Convert]::ToBase64String([IO.File]::ReadAllBytes('扩展.mobileprovision')) |
  gh secret set IOS_WIDGET_PROFILE_BASE64 --env ios-signing --repo FelixZoe/qingxu

[Convert]::ToBase64String([IO.File]::ReadAllBytes('证书.p12')) |
  gh secret set IOS_CERTIFICATE_P12_BASE64 --env ios-signing --repo FelixZoe/qingxu
```

密码使用交互输入：

```powershell
gh secret set IOS_CERTIFICATE_PASSWORD --env ios-signing --repo FelixZoe/qingxu
gh secret set IOS_SIGNED_ARCHIVE_PASSWORD --env ios-signing --repo FelixZoe/qingxu
```

## 构建与下载

1. 打开仓库 `Actions -> Private Signed iOS`。
2. 点击 `Run workflow`。
3. 构建完成后下载 `ios-signed-encrypted` Artifact。
4. 使用 `IOS_SIGNED_ARCHIVE_PASSWORD` 解压 `.7z`，得到签名 IPA。

工作流会在签名前强制校验两个 App ID、Team ID 和 App Group；任何一项不匹配都会停止，不会生成一个“能够安装但没有灵动岛”的错误包。

> 当前 `RashidKhamitov.mobileprovision` 只授权其他固定 App ID，且没有 Widget 扩展描述文件，不能用于此工作流。必须先获得上述两份匹配的描述文件。
