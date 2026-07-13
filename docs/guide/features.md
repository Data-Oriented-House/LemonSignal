## Reconnect
There are occasions where you `:Disconnect` and end up calling `:Connect` again with a new function, with `:Reconnect` that stops being a problem because reconnecting uses that exact function you passed in your connection and simply links it back to the signal.

:::info
*[:Once](../classes/signal#once) connections retain their behavior, as in they will get disconnected again on the next [:Fire](../classes/signal#fire)*
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

## Signal wrapping
This lets you "turn" an [RBXScriptSignal](https://create.roblox.com/docs/reference/engine/datatypes/RBXScriptSignal) into a `LemonSignal` by firing the latter signal every time the former fires, so you can use all the new API as if the `RBXScriptSignal` had it.

```lua
local bindable = Instance.new("BindableEvent")

local signal = LemonSignal.wrap(bindable.Event)

signal:Connect(function(str: string)
    print("Wrapped", str)
end)

bindable:Fire("signal")
--> Wrapped signal
```
