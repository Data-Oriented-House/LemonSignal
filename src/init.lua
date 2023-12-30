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

--- It binds a function to its arguments
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

-- Connection class
export type Connection = {
	Connected: boolean,
	Disconnect: (Connection) -> (),
	Reconnect: (Connection) -> (),
}

local Connection = {}
Connection.__index = Connection

local function newConnection(signal, fn, ...)
	return setmetatable({
		Connected = true,
		_signal = signal,
		_fn = if not ... then fn else newVariadicFunction(fn, ...),
		_next = false,
	}, Connection)
end

function Connection:Disconnect()
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

function Connection:Reconnect()
	local signal = self._signal
	local head = signal._handlerListHead
	if head then
		self._next = head
	end
	signal._handlerListHead = self
end

-- Signal class
export type Signal<T...> = {
	Connect: (fn: (...any) -> (), T...) -> (),
	-- Disconnect: (Connection) -> (),
	-- Reconnect: (Connection) -> (),
}

local Signal = {}
local SignalMeta = {}
SignalMeta.__index = SignalMeta

function Signal.new(): Signal
	return setmetatable({
		_handlerListHead = false,
	}, SignalMeta)
end

function SignalMeta:Connect(fn: (...any) -> (), ...: any)
	local connection = newConnection(self, fn, ...)
	local head = self._handlerListHead
	if head then
		connection._next = head
	end
	self._handlerListHead = connection
	return connection
end

-- Disconnect all handlers. Since we use a linked list it suffices to clear the
-- reference to the head handler.
function SignalMeta:DisconnectAll()
	self._handlerListHead = false
end

-- Signal:Fire(...) implemented by running the handler functions on the
-- coRunnerThread, and any time the resulting thread yielded without returning
-- to us, that means that it yielded to the Roblox scheduler and has been taken
-- over by Roblox scheduling, meaning we have to make a new coroutine runner.
function SignalMeta:Fire(...: any)
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

-- Implement Signal:Wait() in terms of a temporary connection using
-- a Signal:Connect() which disconnects itself.
function SignalMeta:Wait()
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

-- Implement Signal:Once() in terms of a connection which disconnects
-- itself before running the handler.
function SignalMeta:Once(fn: (...any) -> (), ...: any)
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
