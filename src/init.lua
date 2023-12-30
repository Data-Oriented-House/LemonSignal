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

-- It binds a function to its arguments
local function newVariadicFunction(fn: (...any) -> (), ...: any)
	local args = { ... }
	local len = #args
	return function(...)
		if not ... then
			fn(table.unpack(args))
		else
			local count = #args
			for _, value in { ... } do
				count += 1
				args[count] = value
			end
			fn(table.unpack(args))
			for i = count, len + 1, -1 do
				args[i] = nil
			end
		end
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

local Connection = {}
Connection.__index = Connection

--[=[
	@within Connection

	Disconnects the connection from the signal. May be reconnected later using Connection:Reconnect().

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "TEST1:")

	signal:Fire("Hello world!") -- TEST1: Hello world!

	connection:Disconnect()

	signal:Fire("Goodbye world!")
	```
]=]
function Connection.Disconnect<T...>(self: Connection<T...>)
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
		while prev and prev._next ~= self do
			prev = prev._next
		end
		if prev then
			prev._next = self._next
		end
	end
end

--[=[
	@within Connection

	Reconnects the connection to the signal again. May be disconnected later using Connection:Disconnect().

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "TEST1:")

	signal:Fire("Hello world!") -- TEST1: Hello world!

	connection:Disconnect()

	signal:Fire("Goodbye world!")

	connection:Reconnect()

	signal:Fire("Hello again!") -- TEST1: Hello again!
	```
]=]
function Connection.Reconnect<T...>(self: Connection<T...>)
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
	@interface Signal<U...>
	.Connect (Signal<U...>, fn: (...any) -> (), T...) -> Connection<T...>
	.Once (Signal<U...>, fn: (...any) -> (), T...) -> Connection<T...>
	.Fire (Signal<U...>, U...) -> ()
	.DisconnectAll (Signal<U...>) -> ()
]=]

local Signal = {}
local SignalMeta = {}
SignalMeta.__index = SignalMeta

--[=[
	@within Signal
	@return Signal

	Returns a new signal instance which can be used to connect functions.

	```lua
	local LemonSignal = require(path.to.LemonSignal)

	local signal = LemonSignal.new()
	```
]=]
function Signal.new()
	return setmetatable({
		_handlerListHead = false,
	}, SignalMeta)
end

export type Signal<U...> = typeof(Signal.new(...))

--[=[
	@within Signal
	@return Connection

	Connects a function to the signal and returns the connection. Passed variadic arguments that will always be prepended to fired arguments.

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(function(prefix: string, firedMessage: string)
		print(prefix, firedMessage)
	end, "TEST1:")

	signal:Fire("Hello world!") -- TEST1: Hello world!
	```
]=]
function SignalMeta.Connect<T..., U...>(self: Signal<U...>, fn: (...any) -> (), ...: T...): Connection<T...>
	local cn = setmetatable({
		Connected = true,
		_signal = self,
		_fn = if not ... then fn else newVariadicFunction(fn, ...),
		_next = false,
	}, Connection)

	local head = self._handlerListHead
	if head then
		cn._next = head
	end

	self._handlerListHead = cn
	return cn
end

export type Connection<T...> = typeof(SignalMeta.Connect(...))

--[=[
	@within Signal

	Disconnects all connections currently connected to the signal. They may be reconnected later.

	```lua
	local signal = LemonSignal.new()

	local connection1 = signal:Connect(print, "TEST1:")
	local connection2 = signal:Connect(print, "TEST2:")

	signal:Fire("Hello world!")
	-- TEST2: Hello world!
	-- TEST1: Hello world!

	signal:DisconnectAll()

	signal:Fire("Goodbye World!")
	```
]=]
function SignalMeta.DisconnectAll<U...>(self: Signal<U...>)
	-- Disconnect all handlers. Since we use a linked list it suffices to clear the
	-- reference to the head handler.

	self._handlerListHead = false
end

--[=[
	@within Signal

	Fires the signal and calls all connected functions with the connection's bound arguments and the fired arguments.

	```lua
	local signal = LemonSignal.new()

	local connection = signal:Connect(print, "TEST1:")

	signal:Fire("Hello world!") -- TEST1: Hello world!
	```
]=]
function SignalMeta.Fire<U...>(self: Signal<U...>, ...: U...)
	-- Signal:Fire(...) implemented by running the handler functions on the
	-- coRunnerThread, and any time the resulting thread yielded without returning
	-- to us, that means that it yielded to the Roblox scheduler and has been taken
	-- over by Roblox scheduling, meaning we have to make a new coroutine runner.

	local item = self._handlerListHead
	while item do
		if not freeRunnerThread then
			freeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
			-- Get the freeRunnerThread to the first yield
			coroutine.resume(freeRunnerThread)
		end

		local passed, message = coroutine.resume(freeRunnerThread, item._fn, ...)
		if not passed then
			error(message, 2)
		end
		item = item._next
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
function SignalMeta.Wait<U...>(self: Signal<U...>): U...
	-- Implement Signal:Wait() in terms of a temporary connection using
	-- a Signal:Connect() which disconnects itself.

	local waitingCoroutine = coroutine.running()
	local cn
	cn = SignalMeta.Connect(self, function(...)
		Connection.Disconnect(cn)
		local passed, message = coroutine.resume(waitingCoroutine, ...)
		if not passed then
			error(message, 2)
		end
	end)
	return coroutine.yield()
end

--[=[
	@within Signal

	Connects a function to a signal and disconnects if after the first fire. Can be reconnected later.

	```lua
	local signal = Signal.new()

	local connection = signal:Once(print, "TEST1:")

	signal:Fire("Hello world!") -- TEST1: Hello world!

	signal:Fire("Goodbye World!")
	```
]=]
function SignalMeta.Once<T..., U...>(self: Signal<U...>, fn: (...any) -> (), ...: T...)
	-- Implement Signal:Once() in terms of a connection which disconnects
	-- itself before running the handler.

	if ... then
		fn = newVariadicFunction(fn, ...)
	end

	local cn
	cn = SignalMeta.Connect(self, function(...)
		if cn.Connected then
			Connection.Disconnect(cn)
		end
		fn(...)
	end)
	return cn
end

return Signal
