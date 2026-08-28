# iOS 签名、扩展与私密云端构建

公开 Release 提供包含 Widget/Live Activity 扩展的未签名 IPA。要在真机安装，必须使用自己的 Apple 身份重新签名；若希望由 GitHub Actions 完成签名，可使用仓库中的 `Private Signed iOS` 手动工作流。

返回：[项目首页](../README.md) · [Apple 客户端](../apps/apple/README.md)

## 必须保持的标识

| 目标 | 标识 |
| --- | --- |
| 主应用 Bundle ID | `one.darker.qingxu` |
| Widget/Live Activity 扩展 Bundle ID | `one.darker.qingxu.widgets` |
| App Group | `group.one.darker.qingxu` |

主应用和扩展必须属于同一个 Apple Developer Team。两份描述文件都必须授权 App Group，并覆盖目标设备的 UDID（若分发类型需要设备列表）。

## 为什么应用能打开，灵动岛却没有

灵动岛和锁屏实时活动由 `QingxuWidgets.appex` 提供，而不是主应用中的普通页面。以下任一情况都会让系统扩展失效：

- 签名工具只签了 `Qingxu.app`，没有递归签名 `PlugIns/QingxuWidgets.appex`。
- 重签时删除了扩展目录。
- 主应用或扩展 Bundle ID 被随机修改。
- 两者使用不同 Team，或 App Group 权限没有同时保留。
- 描述文件没有授权扩展 App ID、App Group 或当前设备。
- 安装新包时身份与旧包不同，导致覆盖安装失败或共享容器变化。

这些能力不要求应用已经上架 App Store。决定是否可用的是设备系统版本、扩展打包、签名身份和 entitlements。

## 方案一：本机 Apple ID 签名

适合个人设备调试：

1. 在 macOS 上用 Xcode 打开 `apps/apple/QingxuApple.xcodeproj`。
2. 为 `QingxuiOS` 和 `QingxuWidgets` 选择同一个 Team。
3. 确认两个 Bundle ID 和 App Group 未被改成随机值。
4. 选择真机运行，或 Archive 后导出适合自己账号的安装包。

免费个人 Team、付费开发者账号和不同自签工具的权限能力并不完全相同。若工具无法同时创建扩展 App ID 和 App Group，应改用支持这些权限的开发者账号/描述文件，而不是删除扩展。

## 方案二：GitHub 私密云端签名

`Private Signed iOS` 工作流会：

1. 从 GitHub Environment Secrets 导入证书和两份描述文件。
2. 校验 Team、两个 App ID 和 App Group。
3. 同时 Archive 并验证主应用与 Widget 扩展。
4. 生成签名 IPA。
5. 使用 AES-256 和文件名加密生成 `.7z`，只上传加密包。

签名 IPA不会进入公开 Release。加密 Artifact 保留 1 天。

### 配置 GitHub Environment

在仓库 `Settings → Environments` 中创建 `ios-signing`，添加以下 Secrets：

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | 与描述文件匹配的代码签名证书 `.p12` 的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 密码 |
| `IOS_MAIN_PROFILE_BASE64` | 主应用 `.mobileprovision` 的 Base64 |
| `IOS_WIDGET_PROFILE_BASE64` | 扩展 `.mobileprovision` 的 Base64 |
| `IOS_SIGNED_ARCHIVE_PASSWORD` | 至少 16 位的私密压缩包密码 |

PowerShell 写入二进制 Secrets：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('主应用.mobileprovision')) |
  gh secret set IOS_MAIN_PROFILE_BASE64 --env ios-signing --repo FelixZoe/qingxu

[Convert]::ToBase64String([IO.File]::ReadAllBytes('扩展.mobileprovision')) |
  gh secret set IOS_WIDGET_PROFILE_BASE64 --env ios-signing --repo FelixZoe/qingxu

[Convert]::ToBase64String([IO.File]::ReadAllBytes('证书.p12')) |
  gh secret set IOS_CERTIFICATE_P12_BASE64 --env ios-signing --repo FelixZoe/qingxu
```

密码使用交互输入，避免出现在命令历史：

```powershell
gh secret set IOS_CERTIFICATE_PASSWORD --env ios-signing --repo FelixZoe/qingxu
gh secret set IOS_SIGNED_ARCHIVE_PASSWORD --env ios-signing --repo FelixZoe/qingxu
```

### 运行与下载

1. 打开仓库 `Actions → Private Signed iOS`。
2. 点击 `Run workflow`；版本号留空时读取当前项目版本。
3. 构建成功后下载 `qingxu-ios-signed-encrypted` Artifact。
4. 使用 `IOS_SIGNED_ARCHIVE_PASSWORD` 解压 `.7z`。
5. 安装解压得到的签名 IPA。

工作流校验不通过时不会退化生成“能安装但没有扩展”的包，而是直接失败并在日志中指出不匹配项。

## 覆盖安装与更新

要覆盖旧版本并保留数据，至少保持：

- 主应用 Bundle ID 不变。
- 签名 Team/身份兼容。
- App Group 不变。
- 新包版本号或构建号高于旧包。

自签版不能像 App Store 应用一样静默替换自身。应用内“检查更新”会跳转最新版下载，之后仍需使用同一签名方式安装新版 IPA。

## 安装前检查

在 macOS 上解压 IPA 后，可确认扩展是否存在：

```bash
unzip -q Qingxu-*.ipa -d qingxu-ipa-check
test -d qingxu-ipa-check/Payload/Qingxu.app/PlugIns/QingxuWidgets.appex
codesign --verify --deep --strict --verbose=2 qingxu-ipa-check/Payload/Qingxu.app
codesign -d --entitlements :- qingxu-ipa-check/Payload/Qingxu.app
codesign -d --entitlements :- qingxu-ipa-check/Payload/Qingxu.app/PlugIns/QingxuWidgets.appex
```

主应用和扩展的 entitlements 中都应出现 `group.one.darker.qingxu`。

## 密钥安全

- 不要把 `.p12`、密码、描述文件或解密后的签名 IPA提交到仓库。
- GitHub 会在日志中屏蔽 Secret，但拥有仓库写权限的人可以修改工作流引用 Secrets；不要授予不可信账号写权限。
- 为 `ios-signing` Environment 配置审批规则，可以避免工作流被未经确认地读取签名材料。
- 证书疑似泄漏时，应在 Apple Developer 后台撤销并重新生成，而不是只删除聊天或仓库文件。
