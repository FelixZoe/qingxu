# 启动图资源说明

此目录属于共享的 iOS Assets Catalog。当前 SwiftUI 主应用优先使用 `project.yml` 中配置的系统启动背景；目录仍保留用于兼容历史工程和资源目录结构。

如需替换图片：

1. 保持 `Contents.json` 中的文件名、比例和 idiom 对应关系。
2. 提供匹配的 1x、2x、3x PNG，避免透明边缘和低分辨率拉伸。
3. 在 Xcode 的 Assets Catalog 中预览浅色、深色和不同设备尺寸。
4. 同时确认 `apps/apple/project.yml` 的 `UILaunchScreen` 配置，避免启动背景与首屏颜色闪变。

正式应用图标不在此目录维护，请使用 `AppIcon.appiconset` 和 `assets/branding` 中的品牌源文件。
