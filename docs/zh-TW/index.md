# 清序文件

清序是一款為個人設計、本機優先的任務與專注工具，支援 iPhone、Android、Mac 與 Windows。資料預設保存在每台裝置上，需要即時同步時可連接自己的伺服器。

## 從這裡開始

| 目標 | 文件 |
| --- | --- |
| 部署自己的同步服務 | [自託管同步](/zh-TW/DEPLOYMENT) |
| 連接所有用戶端 | [用戶端設定](/zh-TW/DEPLOYMENT#連接用戶端) |
| 下載最新版本 | [GitHub Releases](https://github.com/FelixZoe/qingxu/releases/latest) |

## 最短部署路徑

1. 在 Linux 伺服器安裝 Docker 與 Docker Compose。
2. 將 `.env.example` 複製為 `.env`。
3. 產生 64 位十六進位 `SYNC_TOKEN`。
4. 啟動服務並透過 HTTPS 反向代理公開。
5. 在每台裝置填入相同的伺服器網址與同步金鑰。

清序只面向單一使用者，請勿把同一組網址和金鑰分享給無關使用者。
