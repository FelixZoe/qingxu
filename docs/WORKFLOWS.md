# 构建与发布

仓库只保留三个职责明确的 GitHub Actions 工作流：正式构建与发布、文档部署、私有 iOS 签名。产品截图和预览图不再由 CI 生成，避免模拟器截图占用构建时间和 Release 空间。

返回：[文档首页](/) · [自托管部署](/DEPLOYMENT) · [iOS 私有签名](/IOS_PRIVATE_SIGNING)

## 版本规则

版本号固定为 `主版本.功能版本.修订版本`，每段范围是 `0` 到 `9`。

| 变化 | 示例 | 使用场景 |
| --- | --- | --- |
| 修订版本 | `0.2.1 → 0.2.2` | 修复、细节优化、兼容性调整 |
| 功能版本 | `0.2.9 → 0.3.0` | 修订位进位或一组可见新功能 |
| 主版本 | `0.9.9 → 1.0.0` | 稳定大版本或不兼容变化 |

历史版本使用过长修订号。自动发布会把 `0.1.61` 迁移为 `0.2.0`，此后不会再产生某一段超过一位数字的版本。

## Build and Release

文件：`.github/workflows/build-release.yml`

- Pull Request：运行 Flutter、Go 和各端编译检查，不创建 Release。
- 推送到 `main`：计算下一版本，并行构建 Android、Windows、iOS、macOS 和同步服务镜像。
- 推送 `v*` 标签或手动运行：按指定版本构建；版本必须满足三段单数字规则。
- 所有必要任务成功后才创建或更新 GitHub Release。
- 发布完成后把相同版本回写 Flutter 与 Apple 工程，提交带 `[skip ci]`，避免递归构建。

公开产物包括 APK、Windows 便携包与安装包、未签名 IPA、macOS 压缩包与 DMG、校验和和构建来源证明。Docker 镜像发布到 `ghcr.io/felixzoe/qingxu-sync`。

Android 和 Windows 签名密钥均为可选：未配置时仍构建未签名产物；配置后工作流自动签名。相关 Secrets 为：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `WINDOWS_SIGNING_CERTIFICATE`
- `WINDOWS_SIGNING_PASSWORD`

## Documentation

文件：`.github/workflows/docs.yml`

修改 `docs/**` 或文档工作流后会执行 VitePress 构建。推送到 `main` 时，构建结果通过 SSH 原子部署到 `todo.darker.one`；Pull Request 只验证文档可以构建。

所需 Secrets：

- `DEPLOY_HOST`
- `DEPLOY_USER`
- `DEPLOY_SSH_KEY`
- `DEPLOY_KNOWN_HOSTS`

服务器每次创建独立发布目录，上传完成后再切换 `current` 软链接，避免部署到一半时出现残缺页面。

## Private Signed iOS

文件：`.github/workflows/ios-private-signed.yml`

该工作流只能手动运行，使用 `ios-signing` Environment 中的私密证书和描述文件构建已签名 IPA，并将结果加密为仅当前仓库可下载的 Artifact，不发布到公开 Release。

所需 Secrets：

- `IOS_CERTIFICATE_P12_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `IOS_MAIN_PROFILE_BASE64`
- `IOS_WIDGET_PROFILE_BASE64`
- `IOS_SIGNED_ARCHIVE_PASSWORD`

签名文件必须同时覆盖主应用 `one.darker.qingxu`、扩展 `one.darker.qingxu.widgets` 和 App Group `group.one.darker.qingxu`。完整准备步骤见 [iOS 私有签名](/IOS_PRIVATE_SIGNING)。

## 失败时先看哪里

1. 先打开失败的 Job，不要只看工作流顶部的总状态。
2. `flutter-checks` 失败先在 `apps/flutter` 运行 `flutter analyze` 和 `flutter test`。
3. `sync-server` 失败先在 `services/sync` 运行 `go test ./...` 和 `go vet ./...`。
4. Apple 编译失败先确认 Xcode 版本、XcodeGen 生成结果和扩展 entitlements。
5. 文档部署失败先检查四个 `DEPLOY_*` Secrets 和服务器 `known_hosts`。
6. 某个平台失败时不会发布不完整的新版本；修复后重新推送即可。
