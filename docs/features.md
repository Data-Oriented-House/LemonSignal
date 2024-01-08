---
sidebar_position: 2
---

# Features
In addition to the features you'd expect from a signal, LemonSignal provides two additional features that make working with signals that much better.

## Reconnect
There are occasions where you `:Disconnect` and end up calling `:Connect` again with a new function, with `:Reconnect` that stops being a problem because reconnecting uses that exact function you passed in your connection and simply links it back to the signal.

:::info
*[:Once](../api/Signal#Once) connections retain their behavior, as in they will get disconnected again on the next [:Fire](../api/Signal#Fire)*
:::

```lua
local signal = LemonSignal.new()

local connection1 = signal:Connect(function()
    print("Used Connect")
end)

local connection2 = signal:Once(function()
    print("Used Once")
end)

signal:Fire()
--> Used Once
--> Used Connect

connection1:Disconnect()

signal:Fire() -- both connections are disconnected, nothing will fire

connection1:Reconnect()
connection2:Reconnect()

signal:Fire()
--> Used Once
--> Used Connect

print(connection2.Connected) -- prints false, the :Once connection retains its behavior

signal:Fire()
--> Used Connect
```

## Variadics
Another cool feature is the ability to connect a function while passing varargs which, for example, allows you to use the same function for all your objects for a clean and [flyweight](https://en.wikipedia.org/wiki/Flyweight_pattern) code.

:::info
*[:Fire](../api/Signal#Fire) varargs get appended to a connection's varargs, meaning that [:Connect](../api/Signal#Connect) and [:Once](../api/Signal#Once) varargs will always come before `:Fire`'s*

:::

```lua
local signal = LemonSignal.new()

local function foo(str1: string, str2: string)
    print(str1 .. " " .. str2)
end

signal:Connect(foo, "Hello")

signal:Fire("world!")
--> Hello world!
```

