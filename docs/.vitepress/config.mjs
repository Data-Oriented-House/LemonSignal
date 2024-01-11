import { defineConfig } from 'vitepress'

// https://vitepress.dev/reference/site-config
export default defineConfig({
    title: 'LemonSignal',
    base: '/LemonSignal/',
    description: 'A pure Luau signal implementation.',
    head: [['link', { rel: 'icon', href: '/favicon.ico' }]],
    themeConfig: {
        // https://vitepress.dev/reference/default-theme-config
        nav: [
            { text: 'Guide', link: '/guide/what-is-lemonsignal' },
            { text: 'Api Reference', link: '/classes/signal' }
        ],

        sidebar: {
            '/guide/': [
                {
                    text: 'Introduction',
                    items: [
                        { text: 'What is LemonSignal?', link: '/guide/what-is-lemonsignal' },
                        { text: 'Features', link: '/guide/features' },
                        { text: 'Performance', link: '/guide/performance' },
                    ]
                }
            ],
            'classes': [
                {
                    text: 'Classes',
                    items: [
                        { text: 'Signal', link: '/classes/signal' },
                        { text: 'Connection', link: '/classes/connection' },
                    ]
                }
            ]
        },

        socialLinks: [
            { icon: 'github', link: 'https://github.com/Data-Oriented-House/LemonSignal' }
        ]
    }
})
