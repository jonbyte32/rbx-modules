-- Signal ; @jonbyte ; 2023
--!strict
local signal = {}
signal.__index = signal

-- types
type Function<T...> = (T...) -> ()
type Config = { parallel: boolean, async: boolean, once: boolean }

-- private
local debugWarn: Function<...any>
local function getDebugWarn()
	debugWarn = script:GetAttribute("DebugEnabled") and warn or (function()end)
end
script:GetAttributeChangedSignal("DebugEnabled"):Connect(getDebugWarn)
getDebugWarn()

local function runAsync(cn: Connection, fn: Function<...any>): nil
	while true do
		cn._active = false
		fn(coroutine.yield())
	end
	return nil
end

local function Disconnect(self: Connection): nil
	self._cache[self] = nil
	self.Connected = false
	if self.Async then
		task.cancel(self._thread :: thread)
	end
	return nil
end

function signal:Connect<T...>(fn: Function<T...>): Connection
	-- ASSUMPTION: more often than not, connections are non-blocking
	-- so they will not be async by default
	local cn = {
		_cache = self._cache,
		Once = false,
		Async = false,
		Connected = true,
		Disconnect = Disconnect
	}
	self._cache[cn] = fn
	return cn
end

function signal:Once<T...>(fn: Function<T...>): Connection
	local cn = self:Connect(fn)
	cn.Once = true
	return cn
end

function signal:Async<T...>(fn: Function<T...>): Connection
	local cn: Connection = self:Connect(fn)
	cn.Async = true
	-- each async connection gets its own thread to execute in
	-- IMPORTANT: if connection is already running and Fire happens
	--  the system will resume the connection in its running state
	cn._thread = task.spawn(runAsync, cn, fn)
	return cn
end

function signal:ConnectParallel<T...>(fn: Function<T...>): Connection
	return self:Connect(function(...)
		task.desynchronize()
		fn(...)
	end)
end

function signal:ConnectWith<T...>(mods: Config, fn: Function<T...>): Connection
	local cn = mods.parallel and self:ConnectParallel(fn) or self:Connect(fn)
	cn.Once = mods.once or false
	cn.Async = mods.async or false
	return cn
end

local function Fire<T...>(self, exec: Function<...any>, seconds: number, ...: T...): nil
	local cache = self._cache
	for cn, fn in cache do
		-- could use Connected as a flag to prevent invocation
		-- 	but still keep the connection in the cache.
		if cn.Connected then
			-- disconnect 'once' flagged connections first so
			-- 	they cannot get invoked again in the case of
			-- 	recursive calls to Fire
			if cn.Once then
				cache[cn] = nil
			end
			-- if a connection is non-blocking there is no
			-- 	need to spawn threads. the 'async' flag indicates
			-- 	the connection is blocking
			if cn.Async then
				if cn._active then
					debugWarn(`signal '{self.Name}' resuming active connection`)
				end
				cn._active = true
				if seconds < 0 then
					exec(cn._thread, ...)
				else
					exec(seconds, cn._thread, ...)
				end
			else
				fn(...)
			end
		end
	end
	return nil
end

function signal:Fire<T...>(...: T...): nil
	return Fire(self, task.spawn, -1, ...)
end

function signal:Defer<T...>(...: T...): nil
	return Fire(self, task.defer, -1, ...)
end

function signal:Delay<T...>(seconds: number, ...: T...): nil
	return Fire(self, task.delay, seconds, ...)
end

function signal:Unsafe<T...>(...: T...): nil
	return Fire(self, coroutine.resume, -1, ...)
end

function signal:Wait<T...>(): (T...)
	local waits = self._waits
	local thread = coroutine.running()
	waits[thread] = true
	local cn = self:Once(function(...)
		waits[thread] = nil
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function signal:Timeout<T...>(seconds: number): (boolean, T...)
	local waits = self._waits
	local thread = coroutine.running()
	local cn
	waits[thread] = task.delay(seconds, function()
		cn:Disconnect()
		task.spawn(thread, false)
	end)
	cn = self:Once(function(...)
		task.cancel(waits[thread])
		waits[thread] = nil
		task.spawn(thread, true, ...)
	end)
	return coroutine.yield()
end

function signal:Clear<T...>(): nil
	for cn in self._cache do
		cn:Disconnect()
	end
	table.clear(self._cache)
	return nil
end

function signal:Destroy<T...>(): nil
	-- Destroy should be used when your intent is to never use the
	-- signal again. Clear will still allow you to deref for gc but
	-- this has better logging
	if next(self._waits) then
		debugWarn(`signal '{self.Name}' is being destroyed with waiting threads`)
	end
	self:Clear()
	return nil
end

export type Connection = {
	_cache: { [Connection]: Function<...any> },
	_active: boolean?,
	_thread: thread?,
	Connected: boolean,
	Once: boolean,
	Async: boolean,
	Disconnect: (self: Connection) -> nil
}

export type Signal<T...> = typeof(signal) & {
	Name: string,
	_cache: { [Connection]: Function<T...> },
	_waits: { [thread]: thread | true }
}

return function(name: string?)
	return setmetatable({
		Name = name or "Signal",
		_cache = {},
		_waits = {}
	}, signal)
end
