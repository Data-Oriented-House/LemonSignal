---
outline: deep
---

# Signal
```lua
type Signal<T...> = {
    RBXScriptConnection: RBXScriptConnection?,

    Connect: <U...>(self: Signal<T...>, fn: (...unknown) -> (), U...) -> Connection<U...>,
    Once: <U...>(self: Signal<T...>, fn: (...unknown) -> (), U...) -> Connection<U...>,
    Wait: (self: Signal<T...>) -> T...,
    Fire: (self: Signal<T...>, T...) -> (),
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}
```

## Constructors

### new
Returns a new signal instance which can be used to connect functions.

```lua
local LemonSignal = require(path.to.LemonSignal)

local signal = LemonSignal.new()
```

### wrap
Returns a new signal instance which fires along with the passed RBXScriptSignal.

```lua
Players.PlayerAdded:Connect(function(player)
print(player, "joined, from RBXScriptSignal")
end)

local playerAdded = LemonSignal.wrap(Players.PlayerAdded)
local connection = playerAdded:Connect(function(player)
print(player, "joined, from LemonSignal")
end)

playerAdded:Wait()
-- Player1 joins after some time passes

--> Player1 joined, from RBXScriptSignal
--> Player1 joined, from LemonSignal

connection:Disconnect()
playerAdded:Wait()
-- Player2 joins after some time passes

--> Player2 joined, from RBXScriptSignal

connection:Reconnect() -- Now we get our hands on more API!
-- Player3 joins after some time passes

--> Player3 joined, from RBXScriptSignal
--> Player3 joined, from LemonSignal

-- It can also be used to mock Roblox event fires.
playerAdded:Fire(playerAdded, Players:FindFirstChildOfClass("Player")) --> Player1 joined, from LemonSignal
```

## Properties

### RBXScriptConnection
The RBXScriptConnection that gets made when using [.wrap](#wrap).
It gets disconnected and removed when using [:Destroy](#Destroy).

```lua
local bindable = Instance.new("BindableEvent")

local signal = LemonSignal.wrap(bindable.Event)

local scriptConnection = signal.RBXScriptConnection

print(signal.RBXScriptConnection) --> Connection

signal:Destroy()

print(scriptConnection.Connected) --> false
print(signal.RBXScriptConnection) --> nil
```

## Methods

### Connect
Connects a function to the signal and returns the [connection](../classes/connection.md). Passed variadic arguments will always be prepended to fired arguments.

```lua
local signal = LemonSignal.new()

local connection1 = signal:Connect(function(str: string)
print(str)
end)

local connection2 = signal:Connect(print, "Hello")

signal:Fire("world!")
--> Hello world!
--> world!
```

### Once
Connects a function to a signal and returns a [connection](../classes/connection.md) which disconnects on the first fire. Can be reconnected later.

```lua
local signal = Signal.new()

local connection = signal:Once(print, "Test:")

signal:Fire("Hello world!") --> Test: Hello world!

print(connection.Connected) --> false
```

### Wait
Yields the coroutine until the signal is fired and returns the fired arguments.

```lua
local signal = LemonSignal.new()

task.delay(1, function()
    signal:Fire("Hello", "world!")
end)

local str1, str2 = signal:Wait()
print(str1) --> Hello
print(str2) --> world!
```

### Fire
Fires the signal and calls all connected functions with the connection's bound arguments and the fired arguments.

```lua
local signal = LemonSignal.new()

local connection = signal:Connect(print, "Test:")

signal:Fire("Hello world!") --> Test: Hello world!
```

### DisconnectAll
Disconnects all connections currently connected to the signal. They may be reconnected later.

```lua
local signal = LemonSignal.new()

local connection1 = signal:Connect(print, "First:")
local connection2 = signal:Connect(print, "Second:")

signal:Fire("Hello world!")
--> Second: Hello world!
--> First: Hello world!

signal:DisconnectAll()

signal:Fire("Goodbye World!")
```

### Destroy
Similar to DisconnectAll but also disconnects the RBXScriptConnection made using `.warp`.
Contrary to the method's name, the signal remains usable.

```lua
local signal = LemonSignal.new()

local connection = signal:Connect(print, "Hello")

signal:Fire("world!")
--> Hello world!

signal:Destroy()

signal:Fire("Goodbye World!")
```