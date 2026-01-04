--[[
Signal
A batched yield-safe signal implementation based on Nevermore's GoodSignal.
More efficient than array-based approaches due to linked list structure.
]]

type ListenerCallback = (...any) -> ()

type Connection = {
	Disconnect: (Connection) -> (),
	Destroy: (Connection) -> (),
	IsConnected: (Connection) -> boolean,
	_signal: Signal?,
	_fn: ListenerCallback?,
	_next: Connection?,
	_memoryCategory: string,
}

export type Signal = {
	Connect: (Signal, ListenerCallback) -> Connection,
	Once: (Signal, ListenerCallback) -> Connection,
	Wait: (Signal) -> ...any,
	Fire: (Signal, ...any) -> (),
	DisconnectAll: (Signal) -> (),
	Destroy: (Signal) -> (),
	GetConnectionCount: (Signal) -> number,
	_handlerListHead: Connection | false,
}

-- Connection class
local Connection = {}
Connection.__index = Connection
Connection.ClassName = "Connection"

function Connection.new(signal: Signal, fn: ListenerCallback): Connection
	return setmetatable({
		_memoryCategory = debug.getmemorycategory(),
		_signal = signal,
		_fn = fn,
	}, Connection) :: any
end

function Connection:IsConnected(): boolean
	return rawget(self :: any, "_signal") ~= nil
end

function Connection:Disconnect()
	local signal = rawget(self :: any, "_signal")
	if not signal then
		return
	end

	-- Unhook the node from the linked list
	local ourNext = rawget(self :: any, "_next")

	if signal._handlerListHead == self then
		signal._handlerListHead = ourNext or false
	else
		local prev = signal._handlerListHead
		while prev and rawget(prev, "_next") ~= self do
			prev = rawget(prev, "_next")
		end
		if prev then
			rawset(prev, "_next", ourNext)
		end
	end

	-- Clear all member variables for GC
	table.clear(self :: any)
end

Connection.Destroy = Connection.Disconnect

-- Signal class
local Signal = {}
Signal.__index = Signal
Signal.ClassName = "Signal"

-- Free thread pool for efficient handler execution
local freeThreads = setmetatable({} :: { [string]: thread }, { __mode = "kv" })

local function acquireRunnerThreadAndCallEventHandler(memoryCategory: string, fn: (...any) -> (), ...)
	local acquiredRunnerThread = freeThreads[memoryCategory]
	freeThreads[memoryCategory] = nil
	fn(...)
	freeThreads[memoryCategory] = acquiredRunnerThread
end

local function runEventHandlerInFreeThread(...)
	acquireRunnerThreadAndCallEventHandler(...)
	while true do
		acquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

local function fire(memoryCategory: string, fn: (...any) -> (), ...)
	local thread = freeThreads[memoryCategory]
	if not thread then
		thread = coroutine.create(runEventHandlerInFreeThread)
		freeThreads[memoryCategory] = thread
	end
	task.spawn(thread, memoryCategory, fn, ...)
end

function Signal.new(): Signal
	return setmetatable({
		_handlerListHead = false,
	}, Signal) :: any
end

function Signal:Connect(callback: ListenerCallback): Connection
	assert(type(callback) == "function", "Signal:Connect expects a function")

	local connection = Connection.new(self, callback)
	if self._handlerListHead then
		rawset(connection :: any, "_next", self._handlerListHead)
		self._handlerListHead = connection
	else
		self._handlerListHead = connection
	end
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

	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

function Signal:Fire(...)
	local connection: any = self._handlerListHead
	while connection do
		-- Capture next node before firing (in case of disconnect during fire)
		local nextNode = rawget(connection, "_next")

		if rawget(connection, "_signal") ~= nil then -- isConnected
			fire(connection._memoryCategory, connection._fn, ...)
		end

		connection = nextNode
	end
end

function Signal:GetConnectionCount(): number
	local n = 0
	local prev: any = self._handlerListHead
	while prev do
		n += 1
		prev = rawget(prev, "_next")
	end
	return n
end

function Signal:DisconnectAll()
	while self._handlerListHead do
		local last = self._handlerListHead
		last:Disconnect()
	end
	self._handlerListHead = false
end

Signal.Destroy = Signal.DisconnectAll

return Signal
