---
sidebar_position: 3
---

# Performance
LemonSignal's `:Fire` uses [coroutine.resume](https://create.roblox.com/docs/reference/engine/libraries/coroutine#resume) instead of [task.spawn](https://create.roblox.com/docs/reference/engine/libraries/task#spawn) because `resume` is a whopping ~80% faster than `spawn` while behaving functionally the same. This makes LemonSignal objectively faster than any signal that uses `task.spawn` like [GoodSignal](https://github.com/stravant/goodsignal). The only nuisance with this approach is that debugging is less convenient, the next page talks about how to mitigate this issue.

Using [boatbomber's bechmarker plugin](https://boatbomber.itch.io/benchmarker) we can measure how much faster this approach is, please note that the execution times are not representative of how much time a single method takes to run, they are only meant to show the difference in speed relative to eachother which is still valuable insight.

![Benchmark](/benchmark.png)

As you can see, LemonSignal's `:Fire` runs ~70% faster than GoodSignal's while also providing a whole slew of new features!