--[[
Promise
A lightweight Promise implementation for Roblox Lua.

Inspired by Promises/A+ semantics and NevermoreEngine conventions.
Designed for ease of use within the Roblox environment.
]]

local Promise = {}
Promise.__index = Promise

-- Promise States
local STATUS_PENDING = "Pending"
local STATUS_FULFILLED = "Fulfilled"
local STATUS_REJECTED = "Rejected"

-- Introspection helpers
function Promise.is(value)
	return type(value) == "table" and type(value.andThen) == "function"
end

function Promise.from(value)
	if Promise.is(value) then
		return value
	end

	return Promise.resolve(value)
end

-- Static constructors
function Promise.resolve(value)
	if Promise.is(value) then
		return value
	end

	return Promise.new(function(resolve)
		resolve(value)
	end)
end

function Promise.reject(reason)
	return Promise.new(function(_, reject)
		reject(reason)
	end)
end

function Promise.all(list)
	return Promise.new(function(resolve, reject)
		local remaining = #list
		if remaining == 0 then
			resolve({})
			return
		end

		local results = table.create(remaining)
		for index, item in ipairs(list) do
			Promise.from(item):andThen(function(value)
				results[index] = value
				remaining = remaining - 1
				if remaining == 0 then
					resolve(results)
				end
			end, reject)
		end
	end)
end

function Promise.race(list)
	return Promise.new(function(resolve, reject)
		if #list == 0 then
			resolve(nil)
			return
		end

		local settled = false
		for _, item in ipairs(list) do
			Promise.from(item):andThen(function(value)
				if settled then
					return
				end
				settled = true
				resolve(value)
			end, function(reason)
				if settled then
					return
				end
				settled = true
				reject(reason)
			end)
		end
	end)
end

function Promise.any(list)
	return Promise.new(function(resolve, reject)
		local remaining = #list
		if remaining == 0 then
			reject({})
			return
		end

		local errors = table.create(remaining)
		for index, item in ipairs(list) do
			Promise.from(item):andThen(resolve, function(reason)
				errors[index] = reason
				remaining = remaining - 1
				if remaining == 0 then
					reject(errors)
				end
			end)
		end
	end)
end

function Promise.allSettled(list)
	return Promise.new(function(resolve)
		local remaining = #list
		if remaining == 0 then
			resolve({})
			return
		end

		local results = table.create(remaining)
		for index, item in ipairs(list) do
			Promise.from(item):andThen(function(value)
				results[index] = { status = "fulfilled", value = value }
				remaining = remaining - 1
				if remaining == 0 then
					resolve(results)
				end
			end, function(reason)
				results[index] = { status = "rejected", reason = reason }
				remaining = remaining - 1
				if remaining == 0 then
					resolve(results)
				end
			end)
		end
	end)
end

function Promise.delay(seconds, value)
	return Promise.new(function(resolve)
		task.delay(seconds, resolve, value)
	end)
end

function Promise.each(list, fn)
	return Promise.new(function(resolve, reject)
		local results = table.create(#list)
		local index = 1

		local function step()
			if index > #list then
				resolve(results)
				return
			end

			local ok, result = pcall(fn, list[index], index)
			if not ok then
				reject(result)
				return
			end

			Promise.from(result):andThen(function(value)
				results[index] = value
				index = index + 1
				step()
			end, reject)
		end

		step()
	end)
end

-- Creates a new Promise
function Promise.new(executor)
	local self = setmetatable({}, Promise)
	self._status = STATUS_PENDING
	self._value = nil
	self._reason = nil
	self._fulfilledCallbacks = {}
	self._rejectedCallbacks = {}

	local function resolve(value)
		if self._status ~= STATUS_PENDING then
			return
		end
		self._status = STATUS_FULFILLED
		self._value = value

		local callbacks = self._fulfilledCallbacks
		self._fulfilledCallbacks = nil
		self._rejectedCallbacks = nil

		for _, callback in ipairs(callbacks) do
			task.defer(callback, value)
		end
	end

	local function reject(reason)
		if self._status ~= STATUS_PENDING then
			return
		end

		self._status = STATUS_REJECTED
		self._reason = reason
		local callbacks = self._rejectedCallbacks
		self._fulfilledCallbacks = nil
		self._rejectedCallbacks = nil

		for _, callback in ipairs(callbacks) do
			task.defer(function()
				local ok, err = pcall(callback, reason)
				if not ok then
					warn("Promise rejection callback error:", err)
				end
			end)
		end
	end

	task.spawn(function()
		local ok, err = pcall(executor, resolve, reject)
		if not ok then
			if self._status == STATUS_PENDING then
				reject(err)
			else
				warn("Promise executor error after settlement:", err)
			end
		end
	end)

	return self
end

-- andThen method for chaining Promises
function Promise:andThen(onFulfilled, onRejected)
	return Promise.new(function(resolve, reject)
		local function handleFulfilled(value)
			if onFulfilled then
				local ok, result = pcall(onFulfilled, value)
				if ok then
					if result and type(result) == "table" and result.andThen then
						-- Result is a Promise, chain it
						result:andThen(resolve, reject)
					else
						resolve(result)
					end
				else
					reject(result)
				end
			else
				resolve(value)
			end
		end

		local function handleRejected(reason)
			if onRejected then
				local ok, result = pcall(onRejected, reason)
				if ok then
					if result and type(result) == "table" and result.andThen then
						-- Result is a Promise, chain it
						result:andThen(resolve, reject)
					else
						resolve(result)
					end
				else
					reject(result)
				end
			else
				reject(reason)
			end
		end

		if self._status == STATUS_FULFILLED then
			task.spawn(function()
				local ok, err = pcall(handleFulfilled, self._value)
				if not ok then
					reject(err)
				end
			end)
		elseif self._status == STATUS_REJECTED then
			task.spawn(function()
				local ok, err = pcall(handleRejected, self._reason)
				if not ok then
					reject(err)
				end
			end)
		else
			table.insert(self._fulfilledCallbacks, handleFulfilled)
			table.insert(self._rejectedCallbacks, handleRejected)
		end
	end)
end

-- Catch method for handling rejections
function Promise:catch(onRejected)
	return self:andThen(nil, onRejected)
end

-- Finally method for cleanup operations
function Promise:finally(onFinally)
	return self:andThen(function(value)
		if onFinally then
			pcall(onFinally)
		end
		return value
	end, function(reason)
		if onFinally then
			pcall(onFinally)
		end
		error(reason)
	end)
end

return Promise
