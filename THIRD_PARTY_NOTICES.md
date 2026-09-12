# 第三方软件声明

清序使用或参考了以下开源项目。各项目版权归原作者所有，具体条款以对应仓库内的许可文件为准。

## 直接依赖

### SwiftTerm

- 仓库：<https://github.com/migueldeicaza/SwiftTerm>
- 用途：iOS 与 macOS 的终端渲染组件。
- 许可：MIT License。
- 稳定版本：`v1.18.0`（固定修订 `7691f85b222a67a66b58499e1b2647443cf0dda7`）

### Citadel

- 仓库：<https://github.com/orlandos-nl/Citadel>
- 用途：SSH 客户端、交互式 TTY 与 SFTP 文件访问。
- 许可：MIT License。
- 固定修订：`ae8562f895de06ccb86fdb1cbb65fd99c8976e12`

### swift-nio-ssh

- 仓库：<https://github.com/Wellz26/swift-nio-ssh>
- 用途：Citadel 使用的 SSH 协议类型，以及清序的主机密钥校验委托。
- 许可：Apache License 2.0。

## 设计与实现参考

### VVTerm

- 仓库：<https://github.com/vivy-company/vvterm>
- 用途：参考同一连接配置下组织服务器状态、终端和文件管理的产品形式。
- 许可：GNU GPL v3。
- 说明：清序没有合并 VVTerm 的完整应用源码、二进制依赖、会员、商店、语音、社区或多用户模块。

### Termini

- 仓库：<https://github.com/arach/Termini>
- 用途：主机密钥 TOFU 存储与指纹校验方案参考。
- 许可：MIT License。
- 参考修订：`d212b998f53645784c6ebd6e35f362e8411988d5`
