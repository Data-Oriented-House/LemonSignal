---
sidebar_position: 3
---

# Performance
LemonSignal takes advantage of Luau's [inline caching](https://luau-lang.org/performance#inline-caching-for-table-and-global-access) to use a doubly linked list to store the connections which makes very fast while also retaining the last connected first fired order, it also uses GoodSignal's coroutine optimization but per signal instead of globally, which helps minimize the amount of coroutines that get created when a connection blocks.

## Benchmark
To verify which implementation is best, I made a barebones version of [singly linked list](https://gist.github.com/Aspecky/9bc1daa8a17d2b698d127eff24e82bf3), [doubly linked list](https://gist.github.com/Aspecky/df557c8e2f486eeb5eee4690e67da312), [unordered array](https://gist.github.com/Aspecky/fa28639259f94ce4586a069b16cf44e3) and [dictionary](https://gist.github.com/Aspecky/4cd07bc64ed1016ee6c73baad24bfb80) signals and benched them using [boatbomber's bechmarker plugin](https://boatbomber.itch.io/benchmarker).

:::note TL;DR
Doubly linked list fires as fast as an array, connects, disconnects and reconnects almost as fast as a dictionary, and unlike the two it retains fire order.
:::

### .new
![new](\benchmarks\new.png)

### :Connect
![connect](\benchmarks\connect.png)

### :Fire
![fire](\benchmarks\fire.png)

### :Disconnect
![disconnect](\benchmarks\disconnect.png)

### :Reconnect
![reconnect](\benchmarks\reconnect.png)

### All of the above
![all](\benchmarks\all.png)

### Conclusion
We can conclude that a doubly linked list strikes the best balance out of the other 3 by having:
* Ordered fire
* Fast iteration making :Fire run as fast as an array
* Solves singly's O(n) disconnect by making it O(1) which makes it as fast as the other 2