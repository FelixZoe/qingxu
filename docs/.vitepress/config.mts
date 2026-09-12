import { defineConfig } from 'vitepress'

const repository = 'https://github.com/FelixZoe/qingxu'
const downloads = `${repository}/releases/latest`

const sharedTheme = {
  logo: '/mark.svg',
  search: { provider: 'local' as const },
  socialLinks: [{ icon: 'github' as const, link: repository }]
}

export default defineConfig({
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['meta', { name: 'theme-color', content: '#f7f9fc' }],
    ['meta', { name: 'color-scheme', content: 'light dark' }]
  ],
  locales: {
    root: {
      label: '简体中文',
      lang: 'zh-CN',
      title: '清序文档',
      description: '清序跨端开发、自托管同步与部署文档',
      themeConfig: {
        ...sharedTheme,
        siteTitle: '清序文档',
        nav: [
          { text: '部署', link: '/DEPLOYMENT' },
          { text: '架构', link: '/ARCHITECTURE' },
          { text: '安全', link: '/SECURITY_PERFORMANCE' },
          { text: '同步协议', link: '/SYNC_PROTOCOL' },
          { text: '下载', link: downloads }
        ],
        sidebar: [
          {
            text: '开始',
            items: [
              { text: '文档首页', link: '/' },
              { text: '产品范围', link: '/PRODUCT' }
            ]
          },
          {
            text: '部署与维护',
            items: [
              { text: '自托管同步', link: '/DEPLOYMENT' },
              { text: 'iOS 私有签名', link: '/IOS_PRIVATE_SIGNING' }
            ]
          },
          {
            text: '开发',
            items: [
              { text: '系统架构', link: '/ARCHITECTURE' },
              { text: '安全与性能审计', link: '/SECURITY_PERFORMANCE' },
              { text: '同步协议', link: '/SYNC_PROTOCOL' },
              { text: '跨端设计规范', link: '/DESIGN' }
            ]
          }
        ],
        outline: { level: 2, label: '本页内容' },
        lastUpdated: { text: '最后更新于' },
        docFooter: { prev: '上一篇', next: '下一篇' },
        footer: {
          message: '个人、本地优先、自托管同步',
          copyright: '清序 Qingxu'
        }
      }
    },
    en: {
      label: 'English',
      lang: 'en-US',
      title: 'Qingxu Documentation',
      description: 'Cross-platform clients and self-hosted sync for Qingxu',
      themeConfig: {
        ...sharedTheme,
        siteTitle: 'Qingxu Docs',
        nav: [
          { text: 'Deploy', link: '/en/DEPLOYMENT' },
          { text: 'Download', link: downloads }
        ],
        sidebar: [
          {
            text: 'Get started',
            items: [
              { text: 'Overview', link: '/en/' },
              { text: 'Self-hosted sync', link: '/en/DEPLOYMENT' }
            ]
          }
        ],
        outline: { level: 2, label: 'On this page' },
        lastUpdated: { text: 'Last updated' },
        docFooter: { prev: 'Previous', next: 'Next' },
        footer: {
          message: 'Personal, local-first, self-hosted sync',
          copyright: 'Qingxu'
        }
      }
    },
    'zh-TW': {
      label: '繁體中文',
      lang: 'zh-TW',
      title: '清序文件',
      description: '清序跨平台用戶端與自託管同步部署文件',
      themeConfig: {
        ...sharedTheme,
        siteTitle: '清序文件',
        nav: [
          { text: '部署', link: '/zh-TW/DEPLOYMENT' },
          { text: '下載', link: downloads }
        ],
        sidebar: [
          {
            text: '開始',
            items: [
              { text: '文件首頁', link: '/zh-TW/' },
              { text: '自託管同步', link: '/zh-TW/DEPLOYMENT' }
            ]
          }
        ],
        outline: { level: 2, label: '本頁內容' },
        lastUpdated: { text: '最後更新於' },
        docFooter: { prev: '上一篇', next: '下一篇' },
        footer: {
          message: '個人、本機優先、自託管同步',
          copyright: '清序 Qingxu'
        }
      }
    }
  }
})
