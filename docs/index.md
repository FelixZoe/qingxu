# 清序开发与部署文档

这里是清序的正式技术文档，覆盖客户端开发、自托管同步、私有 iOS 签名、跨端设计规范和同步协议。清序面向个人使用：数据默认保存在本机，也可以连接你自己的服务器完成实时同步。

## 从这里开始

| 目标 | 文档 |
| --- | --- |
| 部署自己的同步服务 | [自托管部署](/DEPLOYMENT) |
| 配置 iPhone、Android、Mac 与 Windows | [客户端连接](/DEPLOYMENT#连接客户端) |
| 构建并签名 iOS IPA | [iOS 私有签名](/IOS_PRIVATE_SIGNING) |
| 了解客户端与服务端结构 | [系统架构](/ARCHITECTURE) |
| 开发同步能力 | [同步协议](/SYNC_PROTOCOL) |
| 保持四端视觉一致 | [设计规范](/DESIGN) |
| 构建客户端与发布版本 | [构建与发布](/WORKFLOWS) |

## 最短部署路径

1. 在 Linux 服务器安装 Docker 与 Docker Compose。
2. 复制仓库中的 `.env.example` 和 `docker-compose.yml`。
3. 生成 64 位十六进制 `SYNC_TOKEN`，启动服务。
4. 为服务配置 HTTPS 反向代理。
5. 在各端填写同一个服务器根地址、同步密钥和不同的设备名称。

完整命令、1Panel 配置、备份、升级和故障排查见[自托管部署](/DEPLOYMENT)。

## 项目入口

- [GitHub 仓库](https://github.com/FelixZoe/qingxu)
- [下载最新版本](https://github.com/FelixZoe/qingxu/releases/latest)
- [构建状态](https://github.com/FelixZoe/qingxu/actions)
