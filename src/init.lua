--!optimize 2
--!nocheck
--!native

-- The currently idle thread to run the next handler on
local freeRunnerThread = nil

-- Function which acquires the currently idle handler runner thread, runs the
-- function fn on it, and then releases the thread, returning it to being the
-- currently idle one.
-- If there was a currently idle runner thread already, that's okay, that old
-- one will just get thrown and eventually GCed.
local function acquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquiredRunnerThread = freeRunnerThread
	freeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	freeRunnerThread = acquiredRunnerThread
end

-- Coroutine runner that we create coroutines of. The coroutine can be
-- repeatedly resumed with functions to run followed by the argument to run
-- them with.
local function runEventHandlerInFreeThread()
	-- Note: We cannot use the initial set of arguments passed to
	-- runEventHandlerInFreeThread for a call to the handler, because those
	-- arguments would stay on the stack for the duration of the thread's
	-- existence, temporarily leaking references. Without access to raw bytecode
	-- there's no way for us to clear the "..." references from the stack.
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

-- To allow for better error reporting on Roblox, we'll use task.spawn
-- with the erroring function and let the task scheduler log to the output.
-- The if statement exists for normal error reporting outside of Roblox
local function contextualError(fn, ...)
	if task then
		task.spawn(fn, ...)
	else
		local _, message = pcall(fn, ...)
		error(message, 3)
	end
end

--[=[
	@class Connection
]=]

--[=[
	@within Connection
	@interface Connection<T...>
	.Connected boolean
	.Disconnect (Connection<T...>) -> ()
	.Reconnect (Connection<T...>) -> ()
]=]

--[=[
	Indicates whether the connection is connected or not.

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "Hello world!")

	print(connection.Connected) -- true

	connection:Disconnect()

	print(connection.Connected) -- false
	```
	@within Connection
	@prop Connected boolean
	@readonly
]=]

local Connection = {}
Connection.__index = Connection

--[=[
	Disconnects the connection from the signal. May be reconnected later using :Reconnect().

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "Test:")

	signal:Fire("Hello world!") -- Test: Hello world!

	connection:Disconnect()

	signal:Fire("Goodbye world!")
	```

	@within Connection
]=]
function Connection.Disconnect<T...>(self: Connection<T...>)
	if not self.Connected then
		return
	end
	self.Connected = false

	-- Unhook the node, but DON'T clear it. That way any fire calls that are
	-- currently sitting on this node will be able to iterate forwards off of
	-- it, but any subsequent fire calls will not hit it, and it will be GCed
	-- when no more fire calls are sitting on it.
	local signal = self._signal
	if signal._handlerListHead == self then
		signal._handlerListHead = self._next
	else
		local prev = signal._handlerListHead
		local next = prev._next
		while prev and next ~= self do
			prev = next
		end
		if prev then
			prev._next = self._next
		end
	end
end

--[=[
	Reconnects the connection to the signal again. If it's a :Once connection it will be
	disconnected after the next signal fire.

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "Test:")

	signal:Fire("Hello world!") -- Test: Hello world!

	connection:Disconnect()

	signal:Fire("Goodbye world!")

	connection:Reconnect()

	signal:Fire("Hello again!") -- Test: Hello again!
	```

	@within Connection
]=]
function Connection.Reconnect<T...>(self: Connection<T...>)
	if self.Connected then
		return
	end
	self.Connected = true

	local signal = self._signal
	local head = signal._handlerListHead
	if head then
		self._next = head
	end
	signal._handlerListHead = self
end

--[=[
	@class Signal
]=]

--[=[
	@within Signal
	@interface Signal
	.Connect (Signal, fn: (...any) -> (), T...) -> Connection<T...>
	.Once (Signal, fn: (...any) -> (), T...) -> Connection<T...>
	.Fire (Signal, any) -> ()
	.DisconnectAll (Signal) -> ()
]=]

local Signal = {}
local SignalMeta = {}
SignalMeta.__index = SignalMeta

--[=[
	Returns a new signal instance which can be used to connect functions.

	```lua
	local LemonSignal = require(path.to.LemonSignal)

	local signal = LemonSignal.new()
	```

	@within Signal
	@return Signal
]=]
function Signal.new()
	return setmetatable({
		_handlerListHead = false,
	}, SignalMeta)
end

export type Signal = typeof(Signal.new(...))

--[=[
	Connects a function to the signal and returns the connection. Passed variadic arguments will always be prepended to fired arguments.

	```lua
	local signal = LemonSignal.new()

	local connection1 = signal:Connect(function(str: string)
		print(str)
	end)

	local connection2 = signal:Connect(print, "Hello")

	signal:Fire("world!")
	-- Hello world!
	-- world!
	```

	@within Signal
]=]
function SignalMeta.Connect<T...>(self: Signal, fn: (...any) -> (), ...: T...)
	local cn = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
		_next = false,
	}, Connection)

	if ... then
		cn._varargs = { ... }
	end

	local head = self._handlerListHead
	if head then
		cn._next = head
	end

	self._handlerListHead = cn
	return cn
end

export type Connection<T...> = typeof(SignalMeta.Connect(...))

local connect = SignalMeta.Connect
local disconnect = Connection.Disconnect

--[=[
	Connects a function to a signal and disconnects if after the first fire. Can be reconnected later.

	```lua
	local signal = Signal.new()

	local connection = signal:Once(print, "Test:")

	signal:Fire("Hello world!") -- Test: Hello world!

	print(connection.Connected) -- false
	```

	@within Signal
]=]
function SignalMeta.Once<T...>(self: Signal, fn: (...any) -> (), ...: T...)
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

	signal:Fire("Hello world!") -- Test: Hello world!
	```

	@within Signal
]=]
function SignalMeta.Fire(self: Signal, ...: any)
	-- Signal:Fire(...) implemented by running the handler functions on the
	-- coRunnerThread, and any time the resulting thread yielded without returning
	-- to us, that means that it yielded to the Roblox scheduler and has been taken
	-- over by Roblox scheduling, meaning we have to make a new coroutine runner.

	local cn = self._handlerListHead
	while cn do
		if not freeRunnerThread then
			freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
			-- Get the freeRunnerThread to the first yield
			coroutine.resume(freeRunnerThread)
		end

		if not cn._varargs then
			if not coroutine.resume(freeRunnerThread, cn._fn, ...) then
				contextualError(cn._fn, ...)
			end
		else
			local args = cn._varargs
			local len = #args
			local count = len
			for _, value in { ... } do
				count += 1
				args[count] = value
			end

			if not coroutine.resume(freeRunnerThread, cn._fn, table.unpack(args)) then
				contextualError(cn._fn, table.unpack(args))
			end

			for i = count, len + 1, -1 do
				args[i] = nil
			end
		end

		cn = cn._next
	end
end

--[=[
	@within Signal

	Waits until the signal is fired and returns the fired arguments.

	```lua
	local signal = LemonSignal.new()

	task.delay(1, function()
		signal:Fire("Hello", "world!")
	end)

	local str1, str2 = signal:Wait()
	print(str1) -- Hello
	print(str2) -- world!
	```
]=]
function SignalMeta.Wait(self: Signal): ...any
	-- Implement :Wait() in terms of a temporary connection using
	-- a :Connect() which disconnects itself.

	local thread = coroutine.running()
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		coroutine.resume(thread, ...)
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
	-- Second: Hello world!
	-- First: Hello world!

	signal:DisconnectAll()

	signal:Fire("Goodbye World!")
	```

	@within Signal
]=]
function SignalMeta.DisconnectAll(self: Signal)
	-- Disconnect all handlers. Since we use a linked list it suffices to clear the
	-- reference to the head handler.

	self._handlerListHead = false
end

return Signal
