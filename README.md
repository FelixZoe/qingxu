# 清序 Qingxu

一个简洁、离线优先、可自托管同步的个人任务管理器。

## 平台

- Windows：Flutter 原生桌面构建，发布便携 ZIP 和安装版 EXE
- Web：Flutter Web，可部署到任意静态服务器
- iOS：Flutter 客户端，底部使用系统原生 `UITabBar`；iOS 26 自动呈现 Liquid Glass，旧系统保留原生兼容外观

## 当前雏形

已实现今天、收集箱、计划、随时、日志、项目、搜索、快速新增、完成、编辑、删除和本地持久化。同步服务将在下一阶段接入。

## Flutter 本地运行

```powershell
cd apps/flutter
flutter run -d chrome
```

验证与构建：

```powershell
flutter analyze
flutter test
flutter build web --release
flutter build windows --release
```

## iOS 本地构建

iOS 构建需要 macOS 和 Xcode：

```bash
cd apps/flutter
flutter build ios --release --no-codesign
```

## 自动发布

每次推送到 `main`，GitHub Actions 会自动递增补丁版本、检查并构建 Web、Windows 和 iOS，随后创建对应的 GitHub Release，并把新版本号回写到源码。重复运行同一次构建会复用原版本，不会重复跳号。Release 附带：

- `Qingxu-<版本>-Windows-Portable.zip`
- `Qingxu-<版本>-Windows-Setup.exe`
- `Qingxu-<版本>-Web.zip`
- `Qingxu-<版本>-iOS-unsigned.ipa`

也可以推送符合 `v<主版本>.<次版本>.<补丁版本>` 格式的标签来手动发布指定版本。

unsigned IPA 需要使用 SideStore、Sideloadly、AltStore 或其他自签工具签名后安装。
