-- @ Signal, jonbyte, 2023
--!strict

-- types
type Callback<T...> = (T...) -> (...any)

-- thread reuse
local freeThread: thread? = nil
local function execute(thread, fn, ...)
    freeThread = nil
    fn(...)
    freeThread = thread
end
local function main()
    local thread = coroutine.running()
    while true do
        execute(thread, coroutine.yield())
    end
end

local function Disconnect(self: Connection): nil
    self._cache[self._index] = false :: any
    return nil
end

local function Connect<T...>(self: Signal<T...>, exec: Callback<T...>): Connection
    local cache = self._cache
    local index = #cache + 1
    local cn = {
        _cache = cache,
        _exec = exec,
        _index = index,
        Connected = true,
        Yield = true,
        Once = false,
        Disconnect = Disconnect
    }
    cache[index] = cn
    return cn
end

local function Fire(self, resume: any, ...): nil
    local cache = self._cache
    for i, cn in cache do
        if not cn or not cn.Connected then
            continue
        end
        if cn.Yield then
            if not freeThread then
                freeThread = task.spawn(main)
            end
            resume(freeThread, cn._exec, ...)
        else
            cn._exec(...)
        end
        if cn.Once then
            cache[i] = false :: any
        end
    end
    return nil
end

local function FireImmediate<T...>(self: Signal<T...>, ...: T...): nil
    return Fire(self, task.spawn, ...)
end

local function FireDeferred<T...>(self: Signal<T...>, ...: T...): nil
    task.defer(Fire, self, task.spawn, ...)
    return nil
end

local function FireUnsafe<T...>(self: Signal<T...>, ...: T...): nil
    return Fire(self, coroutine.resume)
end

local function Clear<T...>(self: Signal<T...>): nil
    table.clear(self._cache)
    return nil
end

-- exports
export type Connection = {
    _cache      : {Connection},
    _exec       : Callback<...any>,
    _index      : number,
    Connected   : boolean,
    Yield       : boolean,
    Once        : boolean,
    Disconnect  : (self: Connection) -> nil
}
export type Signal<T...> = {
    _cache  : {Connection},
    Connect : typeof(Connect),
    Fire    : typeof(FireImmediate),
    Defer   : typeof(FireDeferred),
    Unsafe  : typeof(FireUnsafe),
    Clear   : typeof(Clear)
}

return function()
    return {
        _cache = {},
        Connect = Connect,
        Fire = FireImmediate,
        Defer = FireDeferred,
        Unsafe = FireUnsafe,
        Clear = Clear
    }
end
