# 四端实时预览

清序的预览图来自真实应用进程，不使用手工绘制的假界面。`Product Previews` 工作流会以同一个提交 SHA 启动 iOS Simulator、Android Emulator、macOS 应用和 Windows 悬浮窗，截取高清图片并覆盖上传到最新 GitHub Release。

## 没有 Android 手机

不需要购买或连接 Android 真机：

1. 打开仓库的 **Actions → Product Previews**。
2. 点击 **Run workflow**。
3. 等待 `android` 任务完成。
4. 在本次运行的 Artifacts 中下载 `preview-android`；全部完成后也可以下载 `qingxu-product-previews`。

每次正式 Release 成功后，该工作流也会自动运行。README 顶部使用 `releases/latest/download/...`，因此会始终展示最新一次成功截图。

## 本机交互预览 Android

需要 Android Studio、Flutter SDK，并在 BIOS/UEFI 中启用 CPU 虚拟化。创建 Pixel 7 或更新机型的 Android 35 模拟器后：

```powershell
cd apps/flutter
flutter pub get
flutter devices
flutter run -d <模拟器 ID>
```

如果 `flutter devices` 看不到模拟器，先在 Android Studio 的 Device Manager 启动虚拟设备，再执行命令。项目首次启动会生成本地示例任务，便于直接检查日程、番茄钟、RSS、天气和设置布局。

## 产物

- `qingxu-product-hero.png`：README/产品站顶部四端主视觉，3840×2160。
- `qingxu-platform-previews.png`：iOS、Android、macOS、Windows 四端 3840×2880 总览。
- `qingxu-preview-<平台>.png`：未经重绘的原始应用截图。

每个平台 artifact 还包含 `preview-<平台>.sha`。发布阶段只有在四个 SHA 完全相同时才合成并上传主视觉，避免把不同版本的界面拼到一起。

工作流只公开应用界面，不会读取或写入个人同步地址、同步密钥、AI 密钥或天气 API 密钥。
