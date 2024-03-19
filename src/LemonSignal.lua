--!optimize 2
--!nocheck
--!native

export type Connection = {
	Connected: boolean,

	Disconnect: (self: Connection) -> (),
	Reconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	RBXScriptConnection: RBXScriptConnection?,

	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

local freeThreads: { thread } = {}

local function runCallback(callback, thread, ...)
	callback(...)
	table.insert(freeThreads, thread)
end

local function yielder()
	while true do
		runCallback(coroutine.yield())
	end
end

local Connection = {}
Connection.__index = Connection

local function disconnect(self: Connection)
	if not self.Connected then
		return
	end
	self.Connected = false

	local next = self._next
	local prev = self._prev

	if next then
		next._prev = prev
	end
	if prev then
		prev._next = next
	end

	local signal = self._signal
	if signal._head == self then
		signal._head = next
	end
end

local function reconnect(self: Connection)
	if self.Connected then
		return
	end
	self.Connected = true

	local signal = self._signal
	local head = signal._head
	if head then
		head._prev = self
	end
	signal._head = self

	self._next = head
	self._prev = false
end

Connection.Disconnect = disconnect
Connection.Reconnect = reconnect

--\\ Signal //--
local Signal = {}
Signal.__index = Signal

-- stylua: ignore
local rbxConnect, rbxDisconnect do
	if task then
		local bindable = Instance.new("BindableEvent")
		rbxConnect = bindable.Event.Connect
		rbxDisconnect = bindable.Event:Connect(function() end).Disconnect
		bindable:Destroy()
	end
end

local function connect<T...>(self: Signal<T...>, fn: (T...) -> ()): Connection
	local head = self._head
	local cn = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
		_next = head,
		_prev = false,
	}, Connection)

	if head then
		head._prev = cn
	end
	self._head = cn

	return cn
end

local function once<T...>(self: Signal<T...>, fn: (T...) -> ())
	local cn
	cn = connect(self, function(...)
		disconnect(cn)
		fn(...)
	end)
	return cn
end

local wait = if task
	then function<T...>(self: Signal<T...>): T...
		local thread = coroutine.running()
		local cn
		cn = connect(self, function(...)
			disconnect(cn)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	else function<T...>(self: Signal<T...>): T...
		local thread = coroutine.running()
		local cn
		cn = connect(self, function(...)
			disconnect(cn)
			local passed, message = coroutine.resume(thread, ...)
			if not passed then
				error(message, 0)
			end
		end)
		return coroutine.yield()
	end

local fire = if task
	then function<T...>(self: Signal<T...>, ...: T...)
		local cn = self._head
		while cn do
			local thread
			if #freeThreads > 0 then
				thread = freeThreads[#freeThreads]
				freeThreads[#freeThreads] = nil
			else
				thread = coroutine.create(yielder)
				coroutine.resume(thread)
			end

			task.spawn(thread, cn._fn, thread, ...)

			cn = cn._next
		end
	end
	else function<T...>(self: Signal<T...>, ...: T...)
		local cn = self._head
		while cn do
			local thread
			if #freeThreads > 0 then
				thread = freeThreads[#freeThreads]
				freeThreads[#freeThreads] = nil
			else
				thread = coroutine.create(yielder)
				coroutine.resume(thread)
			end

			local passed, message = coroutine.resume(thread, cn._fn, thread, ...)
			if not passed then
				print(string.format("%s\nstacktrace:\n%s", message, debug.traceback()))
			end

			cn = cn._next
		end
	end

local function disconnectAll<T...>(self: Signal<T...>)
	local cn = self._head
	while cn do
		disconnect(cn)
		cn = cn._next
	end
end

local function destroy<T...>(self: Signal<T...>)
	disconnectAll(self)
	local cn = self.RBXScriptConnection
	if cn then
		rbxDisconnect(cn)
		self.RBXScriptConnection = nil
	end
end

--\\ Constructors
function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _head = false }, Signal)
end

function Signal.wrap<T...>(signal: RBXScriptSignal): Signal<T...>
	local wrapper = setmetatable({ _head = false }, Signal)
	wrapper.RBXScriptConnection = rbxConnect(signal, function(...)
		fire(wrapper, ...)
	end)
	return wrapper
end

--\\ Methods
Signal.Connect = connect
Signal.Once = once
Signal.Wait = wait
Signal.Fire = fire
Signal.DisconnectAll = disconnectAll
Signal.Destroy = destroy

return { new = Signal.new, wrap = Signal.wrap }
