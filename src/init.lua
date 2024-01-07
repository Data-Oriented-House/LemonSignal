--!optimize 2
--!nocheck
--!native

export type Connection<U...> = {
	Connected: boolean,
	Disconnect: (self: Connection<U...>) -> (),
	Destroy: (self: Connection<U...>) -> (),
}

export type Signal<T...> = {
	RBXScriptConnection: RBXScriptConnection?,
	Connect: <U...>(self: Signal<T...>, fn: (...unknown) -> (), U...) -> Connection<U...>,
	Once: <U...>(self: Signal<T...>, fn: (...unknown) -> (), U...) -> Connection<U...>,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

--[=[
    @class Connection
]=]

--[=[
    @within Connection
    @interface Connection<U...>
    .Connected boolean
    .Disconnect (Connection<U...>) -> ()
    .Reconnect (Connection<U...>) -> ()
]=]

--[=[
    Indicates whether the connection is connected or not.

    ```lua
    local signal = LemonSignal.new()

    local connection = signal:Connect(print, "Hello world!")

    print(connection.Connected) --> true

    connection:Disconnect()

    print(connection.Connected) --> false
    ```

    @within Connection
    @prop Connected boolean
    @readonly
]=]

--[=[
    @class Signal
]=]

--[=[
    @within Signal
    @interface Signal
    .RBXScriptConnection: RBXScriptConnection?,
    .Connect: <U...>(self: Signal<T...>, fn: (...any) -> (), U...) -> Connection<U...>,
    .Once: <U...>(self: Signal<T...>, fn: (...any) -> (), U...) -> Connection<U...>,
    .Wait: (self: Signal<T...>) -> T...,
    .Fire: (self: Signal<T...>, T...) -> (),
    .DisconnectAll: (self: Signal<T...>) -> (),
    .Destroy: (self: Signal<T...>) -> ()
]=]

--[=[
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

    @within Signal
    @prop RBXScriptConnection RBXScriptConnection?
    @readonly
]=]

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(signal: Signal, fn, ...)
	local acquiredRunnerThread = signal._freeRunnerThread
	signal._freeRunnerThread = false
	fn(...)
	-- The handler finished running, this runner thread is free again.
	signal._freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread(signal: Signal, ...)
	acquireRunnerThreadAndCallEventHandler(signal, ...)
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function contextualError(cn: Connection, message: string)
	if task then
		local fullName = if cn._thread then debug.info(cn._thread, 1, "s") else debug.info(cn._fn, "s")
		local parent = game
		for _, childName in string.split(fullName, ".") do
			parent = parent:FindFirstChild(childName)
			if not parent then
				break
			end
		end
		if parent then
			task.spawn(warn, parent, "<-- Press to select the script.")
		end
	end

	error(message, 0)
end

-- Cached functions to avoid using the `:` which is slightly slower
local disconnectAll
local connect
local fire
local rbxDisconnect
local rbxConnect

local Connection = {}
Connection.__index = Connection

--[=[
    Disconnects the connection from the signal. May be reconnected later using :Reconnect().

    ```lua
    local signal = LemonSignal.new()

    local connection = signal:Connect(print, "Test:")

    signal:Fire("Hello world!") --> Test: Hello world!

    connection:Disconnect()

    signal:Fire("Goodbye world!")
    ```

    @within Connection
    @method Disconnect
    @tag Method
]=]
local function disconnect<U...>(self: Connection<U...>)
	if not self.Connected then
		return
	end
	self.Connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.

	local next = self._next
	local prev = self._prev

	if next then
		next._prev = prev
	end
	if prev then
		prev._next = next
	end

	local signal = self._signal
	if signal._handlerListHead == self then
		signal._handlerListHead = next
	end
end
Connection.Disconnect = disconnect

--[=[
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

    @within Connection
    @method Reconnect
    @tag Method
]=]
function Connection.Reconnect<U...>(self: Connection<U...>)
	if self.Connected then
		return
	end
	self.Connected = true

	local signal = self._signal
	local head = signal._handlerListHead
	if head then
		head._prev = self
	end
	signal._handlerListHead = self

	self._next = head
	self._prev = false
end

local Signal = {}
Signal.__index = Signal

--[=[
    Returns a new signal instance which can be used to connect functions.

    ```lua
    local LemonSignal = require(path.to.LemonSignal)

    local signal = LemonSignal.new()
    ```

    @within Signal
    @return Signal
    @tag Constructor
]=]
function Signal.new<T...>(): Signal<T...>
	return setmetatable({
		_handlerListHead = false,
		_freeRunnerThread = false,
	}, Signal)
end

--[=[
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

    @within Signal
    @return Signal
    @tag Constructor
]=]
function Signal.wrap<T...>(signal: RBXScriptSignal): Signal<T...>
	local lemonSignal = setmetatable({
		_handlerListHead = false,
		_freeRunnerThread = false,
	}, Signal)

	lemonSignal.RBXScriptConnection = rbxConnect(signal, function(...)
		fire(lemonSignal, ...)
	end)

	return lemonSignal
end

--[=[
    Connects a function to the signal and returns the connection. Passed variadic arguments will always be prepended to fired arguments.

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

    @within Signal
    @method Connect
    @tag Method
]=]
function Signal.Connect<T..., U...>(self: Signal<T...>, fn: (...any) -> (), ...: U...): Connection<U...>
	local head = self._handlerListHead
	local cn = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,

		_next = head,
		_prev = false,
	}, Connection)

	if ... then
		cn._varargs = { ... }
	end

	if head then
		head._prev = cn
	end
	self._handlerListHead = cn

	return cn
end

--[=[
    Connects a function to a signal and disconnects if after the first fire. Can be reconnected later.

    ```lua
    local signal = Signal.new()

    local connection = signal:Once(print, "Test:")

    signal:Fire("Hello world!") --> Test: Hello world!

    print(connection.Connected) --> false
    ```

    @within Signal
    @method Once
    @tag Method
]=]
function Signal.Once<T..., U...>(self: Signal<T...>, fn: (...any) -> (), ...: U...)
	-- Implement :Once() in terms of a connection which disconnects
	-- itself before running the handler.
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		fn(...)
	end, ...)
	return cn
end

--[=[
    Fires the signal and calls all connected functions with the connection's bound arguments and the fired arguments.

    ```lua
    local signal = LemonSignal.new()

    local connection = signal:Connect(print, "Test:")

    signal:Fire("Hello world!") --> Test: Hello world!
    ```

    @within Signal
    @method Fire
    @tag Method
]=]
function Signal.Fire<T...>(self: Signal<T...>, ...: any)
	-- :Fire(...) implemented by running the handler functions on the
	-- freeRunnerThread, and any time the resulting thread yielded without returning
	-- to us, that means that it yielded to the Roblox scheduler and has been taken
	-- over by Roblox scheduling, meaning we have to make a new coroutine runner.

	local cn = self._handlerListHead
	while cn do
		local freeRunnerThread = self._freeRunnerThread
		if not freeRunnerThread then
			self._freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
			freeRunnerThread = self._freeRunnerThread
		end

		if not cn._varargs then
			local passed, message = coroutine.resume(freeRunnerThread, self, cn._fn, ...)
			if not passed then
				contextualError(cn, message)
			end
		else
			local args = cn._varargs
			local len = #args
			local count = len
			for _, value in { ... } do
				count += 1
				args[count] = value
			end

			local passed, message = coroutine.resume(freeRunnerThread, self, cn._fn, table.unpack(args))
			if not passed then
				contextualError(cn, message)
			end

			for i = count, len + 1, -1 do
				args[i] = nil
			end
		end

		cn = cn._next
	end
end

--[=[
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

    @within Signal
    @method Wait
    @tag Method
    @yields
]=]
function Signal.Wait<T...>(self: Signal<T...>): ...any
	-- Implement :Wait() in terms of a temporary connection using
	-- a :Connect() which disconnects itself.

	local thread = coroutine.running()
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		local passed, message = coroutine.resume(thread, ...)
		if not passed then
			-- The :Fire call will pick up on this error, cn._thread is used to
			-- to get the script the error originated from, wonky stuff
			cn._thread = thread
			error(message, 0)
		end
	end)
	return coroutine.yield()
end

--[=[
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

    @within Signal
    @method DisconnectAll
    @tag Method
]=]
function Signal.DisconnectAll<T...>(self: Signal<T...>)
	local cn = self._handlerListHead
	while cn do
		disconnect(cn)
		cn = cn._next
	end
end

--[=[
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

    @within Signal
    @method Destroy
    @tag Method
]=]
function Signal.Destroy<T...>(self: Signal<T...>)
	disconnectAll(self)
	local cn = self.RBXScriptConnection
	if cn then
		rbxDisconnect(cn)
		self.RBXScriptConnection = nil
	end
end

disconnectAll = Signal.DisconnectAll
connect = Signal.Connect
fire = Signal.Fire
if task then
	local bindable = Instance.new("BindableEvent")
	rbxConnect = bindable.Event.Connect
	rbxDisconnect = bindable.Event:Connect(function() end).Disconnect
	bindable:Destroy()
end

return { new = Signal.new, wrap = Signal.wrap }
