---
sidebar_position: 3
---

# Performance (Roblox)
LemonSignal's `:Fire` uses [coroutine.resume](https://create.roblox.com/docs/reference/engine/libraries/coroutine#resume) instead of [task.spawn](https://create.roblox.com/docs/reference/engine/libraries/task#spawn) because `resume` is a whopping ~80% faster than `spawn` while behaving functionally the same. This makes LemonSignal objectively faster than any signal that uses `task.spawn` like [GoodSignal](https://github.com/stravant/goodsignal).

You might be rightfully asking what's the catch? And I am here to tell you there's none! While `coroutine.resume` makes debugging less convenient because the Roblox output window doesnt account for it well enough, we can simply go around it by using `task.spawn` **only** when the connection errors so the better error reporting of the task scheduler can take the wheel, best of both worlds!

To measure the huge performance improvement `coroutine.resume` achieves, I used [boatbomber's bechmarker plugin](https://boatbomber.itch.io/benchmarker) and ran the following benchmark:
```lua
--!optimize 2

local N = 1000

local co = coroutine.create(function()
    while true do
        local fn = coroutine.yield()
        fn()
    end
end)
coroutine.resume(co)

return {
    ParameterGenerator = function()
        return
    end,

    Functions = {
        ["task.spawn"] = function(Profiler)
            for i = 1, N do
                task.spawn(co, function()
                    return i
                end)
            end
        end,
        ["coroutine.resume"] = function(Profiler)
            for i = 1, N do
                coroutine.resume(co, function()
                    return i
                end)
            end
        end,
    },
}
```

---

***Bear in mind that the execution times I am about to show dont measure how much time a single `coroutine.resume` or `task.spawn` call will take, we are benchmarking batches of those calls to get consistent results, so we can only use these numbers relatively to eachother.***

---

| Function         | 50th % | Average |
| ---------------- | ------ | ------- |
| task.spawn       | 455 μs | 911 μs  |
| coroutine.resume | 73 μs  | 277 μs  |

Using the 50th percentile we can see that `coroutine.resume` is ~84% faster than `task.spawn`!
