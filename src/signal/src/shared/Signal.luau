--[[
Signal
A lightweight event primitive for decoupled communication with explicit cleanup.
]]

type ListenerCallback = (...any) -> ()

type Connection = {
	Disconnect: (Connection) -> (),
	_connected: boolean,
	_callback: ListenerCallback?,
	_signal: Signal?,
	_index: number,
}

export type Signal = {
	Connect: (Signal, ListenerCallback) -> Connection,
	Once: (Signal, ListenerCallback) -> Connection,
	Wait: (Signal) -> ...any,
	Fire: (Signal, ...any) -> (),
	DisconnectAll: (Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection.new(signal: Signal, callback: ListenerCallback)
	return setmetatable({
		_signal = signal,
		_callback = callback,
		_connected = true,
		_index = 0,
	}, Connection)
end

function Connection:Disconnect()
	if not self._connected then
		return
	end

	self._connected = false
	local signal = self._signal
	if signal then
		signal:_disconnect(self._index)
	end

	self._signal = nil
	self._callback = nil
end

function Signal.new(): Signal
	return setmetatable({
		_listeners = {},
		_deadCount = 0,
	}, Signal)
end

function Signal:_disconnect(index: number)
	local listeners = self._listeners
	if listeners[index] then
		listeners[index] = nil
		self._deadCount += 1
	end

	local total = #listeners
	if self._deadCount > 8 and self._deadCount * 2 > total then
		self:_compact()
	end
end

function Signal:_compact()
	local listeners = self._listeners
	local compacted = table.create(#listeners - self._deadCount)
	local newIndex = 1

	for _, connection in ipairs(listeners) do
		if connection and connection._connected then
			connection._index = newIndex
			compacted[newIndex] = connection
			newIndex += 1
		end
	end

	self._listeners = compacted
	self._deadCount = 0
end

function Signal:Connect(callback: ListenerCallback): Connection
	assert(type(callback) == "function", "Signal:Connect expects a function")

	local connection = Connection.new(self, callback)
	local index = #self._listeners + 1

	connection._index = index
	self._listeners[index] = connection

	return connection
end

function Signal:Once(callback: ListenerCallback): Connection
	assert(type(callback) == "function", "Signal:Once expects a function")

	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		callback(...)
	end)

	return connection
end

function Signal:Wait(): ...any
	local thread = coroutine.running()
	assert(thread, "Signal:Wait must be called from a running coroutine")

	local connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		coroutine.resume(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:Fire(...)
	local listeners = self._listeners
	if #listeners == 0 then
		return
	end

	local args = table.pack(...)
	for index = 1, #listeners do
		local connection = listeners[index]
		if connection and connection._connected then
			task.defer(function()
				if connection._connected and connection._callback then
					local ok, err = pcall(connection._callback, table.unpack(args, 1, args.n))
					if not ok then
						warn("Signal callback error:", err)
					end
				end
			end)
		end
	end
end

function Signal:DisconnectAll()
	local listeners = self._listeners
	for _, connection in ipairs(listeners) do
		if connection then
			connection._connected = false
			connection._signal = nil
			connection._callback = nil
		end
	end

	self._listeners = {}
	self._deadCount = 0
end

return Signal
