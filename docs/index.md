---
# https://vitepress.dev/reference/default-theme-home-page
layout: home

hero:
  text: "A faster and more equipped pure Luau signal."
  actions:
    - theme: brand
      text: Get Started
      link: /guide/what-is-lemonsignal
    - theme: alt
      text: API Reference
      link: /api-examples
  image:
    src: /lemon.png

features:
  - title: ♻ Better thread recycling
    details: Up to 40% speed increase when firing the signal with asynchronous connections.
  - title: 🔌 Reconnect
    details: Reconnect makes it a lot more convenient and efficient to reconnect your connections.
  - title: 💬 Variadic connections 
    details: In addition to passing a function when connecting, you can pass variadics to it too.
---

