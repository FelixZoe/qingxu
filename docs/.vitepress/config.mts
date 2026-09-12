import { defineConfig } from 'vitepress'

export default defineConfig({
  lang: 'zh-CN',
  title: '清序文档',
  description: '清序跨端开发、自托管同步与部署文档',
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['meta', { name: 'theme-color', content: '#f7f9fc' }],
    ['meta', { name: 'color-scheme', content: 'light dark' }]
  ],
  themeConfig: {
    logo: '/mark.svg',
    siteTitle: '清序文档',
    nav: [
      { text: '部署', link: '/DEPLOYMENT' },
      { text: '架构', link: '/ARCHITECTURE' },
      { text: '同步协议', link: '/SYNC_PROTOCOL' },
      { text: '下载', link: 'https://github.com/FelixZoe/qingxu/releases/latest' }
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
          { text: '构建与发布', link: '/WORKFLOWS' },
          { text: '同步协议', link: '/SYNC_PROTOCOL' },
          { text: '跨端设计规范', link: '/DESIGN' }
        ]
      }
    ],
    search: { provider: 'local' },
    outline: { level: [2, 3], label: '本页内容' },
    lastUpdated: { text: '最后更新于' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/FelixZoe/qingxu' }
    ],
    footer: {
      message: '个人、本地优先、自托管同步',
      copyright: '清序 Qingxu'
    }
  }
})
