# 清序 Flutter 客户端

`apps/flutter` 是清序的 Android 与 Windows 客户端。正式 iOS 和 macOS 客户端位于 [`apps/apple`](../apple/README.md)，不使用 Flutter 引擎。

返回：[项目首页](../../README.md) · [设计规范](../../docs/DESIGN.md) · [系统架构](../../docs/ARCHITECTURE.md) · [同步协议](../../docs/SYNC_PROTOCOL.md)

## 平台定位

- **Android**：移动端任务、番茄钟、每日目标、专注热力图、同步与设置。
- **Windows**：低占用桌面辅助端，以置顶计时胶囊、今日任务和系统托盘为主；同时提供便携版与安装版。

`ios/` 和 `macos/` 中仍保留部分共享品牌资源、Widget 源文件与历史工程材料，供 Apple 原生工程复用；不要把它们误认为当前正式 Flutter Apple 客户端。

## 环境

- 当前稳定版 Flutter，Dart SDK 版本满足 `pubspec.yaml`。
- Android：Android Studio、Android SDK 和可用设备/模拟器。
- Windows：Windows 10/11、Visual Studio 的“使用 C++ 的桌面开发”工作负载。

检查环境：

```bash
flutter doctor -v
cd apps/flutter
flutter pub get
```

## 开发运行

Windows：

```bash
flutter run -d windows
```

Android：

```bash
flutter devices
flutter run -d <设备ID>
```

## 质量检查

```bash
flutter analyze
flutter test
```

提交到 `main` 后，GitHub Actions 会再次运行以上检查；任一检查失败都不会发布 Release。

## 本地构建

Android APK：

```bash
flutter build apk --release
```

Windows：

```powershell
flutter build windows --release
```

Release 工作流会在 Windows 产物中补齐 VC Runtime，生成便携 ZIP 和 Inno Setup 安装程序。不要只复制单个 `Qingxu.exe`，运行时 DLL、Flutter 数据目录和插件必须一起分发。

## 数据与同步

- 本地任务写入平台应用数据目录。
- 同步密钥写入 `flutter_secure_storage`。
- `TaskController` 负责本地状态、修订号持久化、同步防抖、变更通知与带抖动的断线退避。
- Android/Windows 与 Apple 客户端使用相同的任务、番茄钟和 RSS 同步文档。

协议细节见 [同步协议 v1](../../docs/SYNC_PROTOCOL.md)，服务器搭建见 [部署说明](../../docs/DEPLOYMENT.md)。

## 版本与发布

版本号位于 `pubspec.yaml`，格式为 `x.y.z+构建号`。正式 Release 由根工作流自动决定下一补丁版本并在发布成功后回写；普通功能提交不要手工创建相同标签。
