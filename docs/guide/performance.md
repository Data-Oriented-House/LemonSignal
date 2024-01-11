# Performance
`LemonSignal` does two main things differently which gives it an edge in performance over similar implementations.

## Implementation
`LemonSignal` uses a doubly linked list implementation because it offers the most features out of the others, to show you that I made a barebones version of [singly linked list](https://gist.github.com/Aspecky/9bc1daa8a17d2b698d127eff24e82bf3), [doubly linked list](https://gist.github.com/Aspecky/df557c8e2f486eeb5eee4690e67da312), [unordered array](https://gist.github.com/Aspecky/fa28639259f94ce4586a069b16cf44e3) and [dictionary](https://gist.github.com/Aspecky/4cd07bc64ed1016ee6c73baad24bfb80) signals and benched them using [boatbomber's bechmarker plugin](https://boatbomber.itch.io/benchmarker).

:::info
The execution times are not meant to measure the absolute time it takes for a method to run, they are only meant to be used relative to eachother to see which one runs faster.
:::

### .new
![new](/benchmarks/new.png)

### :Connect
![connect](/benchmarks/connect.png)

### :Fire
![fire](/benchmarks/fire.png)

### :Disconnect
![disconnect](/benchmarks/disconnect.png)

### :Reconnect
![reconnect](/benchmarks/reconnect.png)

### All of the above
![all](/benchmarks/all.png)

### Conclusion
From the benchmarks above, we can conclude that a doubly linked list strikes the best balance out of the other 3 by having:
* Ordered fire
* Fast iteration making :Fire run as fast as an array
* Solves singly's O(n) disconnect by making it O(1) which makes it as fast as the other 2

All the signal implementations as ModuleScripts are here [signals.rbxm](https://github.com/Data-Oriented-House/LemonSignal/blob/main/docs/public/benchmarks/signals.rbxm)<br>
All the `.bench` ModuleScripts that the benchmarker plugin uses are here [benches.rbxm](https://github.com/Data-Oriented-House/LemonSignal/blob/main/docs/public/benchmarks/benches.rbxm)

## Thread recycling
Recycling a thread aka a coroutine helps [task.spawn](https://create.roblox.com/docs/reference/engine/libraries/task#spawn) and [coroutine.resume](https://create.roblox.com/docs/reference/engine/libraries/coroutine#resume) run significantly faster, about 70%, because those functions wont need to go through the trouble of creating a thread.

[GoodSignal](https://github.com/stravant/goodsignal/blob/b8f2cb7c4c989bb2a9b232cec8ca5b5863bcb7f4/src/init.lua#L27) popularized that pattern for signals but it can be improved, when you fire your signal and your connection's callback is asynchronous (yields), the next connection in queue will be forced to create a new thread and the when the previous one is finally free, it'll just get GC'ed.

```lua
local signal = GoodSignal.new()

signal:Connect(function()
    print("sync")
end)

signal:Connect(function()
    task.wait()
    print("async")
end)

signal:Connect(function()
    print("sync")
end)

signal:Fire()
-- The signal will be forced to create two threads because
-- the middle connection will not return the thread in time
```

So what can we do about this? `LemonSignal` simply caches every thread that gets created by the signal so that next time an async connection fires, it'll most likely find a free thread to run on therefor not wasting any work done, so the longer your game runs the higher the chances there's a free thread for the asyncs and the better performance, this benchmark simulates exactly that and shows the notable ~33% speed increase:

![recycling](/benchmarks/recycling.png)

### Memory
Does this negatively affect memory you might wonder? To answer this, we first need to know when do we create and cache a thread? A thread gets created when a free one isnt available, and that can only happen when our connection is asynchronous because it keeps that free thread for itself until it's done with it, at which point it caches for another connection that needs it. So we only 
First we need to understand that we only create and cache an extra thread when a connection is asynchronous, and even if every connection was asynchronous you'll eventually reach an equilibrium where no new threads will be created and will be exclusively recycled.

To give you a perspective on how little memory the caching uses, it'd take 100k cached threads to raise the heap by a measly ~100mb! And your connections will create nowhere near that amount, so you can rest assured that the memory is being used in a worthy manner.