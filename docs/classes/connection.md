---
outline: deep
---

# Connection
```lua
type Connection<U...> = {
Connected: boolean,

Disconnect: (self: Connection<U...>) -> (),
Reconnect: (self: Connection<U...>) -> (),
}
```

## Properties

### Connected
Indicates whether the connection is connected or not.

```lua
local signal = LemonSignal.new()

local connection = signal:Connect(print, "Hello world!")

print(connection.Connected) --> true

connection:Disconnect()

print(connection.Connected) --> false
```

## Methods

### Disconnect
Disconnects the connection from the signal. May be reconnected later using :Reconnect().

```lua
local signal = LemonSignal.new()

local connection = signal:Connect(print, "Test:")

signal:Fire("Hello world!") --> Test: Hello world!

connection:Disconnect()

signal:Fire("Goodbye world!")
```

### Reconnect
Reconnects the connection to the signal again. If it's a :Once connection it will be
disconnected after the next signal fire.

```lua
local signal = LemonSignal.new()

local connection = signal:Connect(print, "Test:")

signal:Fire("Hello world!") --> Test: Hello world!

connection:Disconnect()

signal:Fire("Goodbye world!")

connection:Reconnect()

signal:Fire("Hello again!") --> Test: Hello again!
```