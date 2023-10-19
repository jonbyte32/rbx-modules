--jonbyte, 2023
--!strict

local signal = {}
signal.__index = signal

-- types
type Callback<T...> = (T...) -> (...any)
type CMods = {noyield: boolean?, unsafe: boolean?, once: boolean?}
type ArgPack = { [number]: any, n: number }
type TYPE_ERROR = any

export type Connection<T...> = {
    _last: Connection<T...>?, _next: Connection<T...>?,
    _signal: Signal<T...>,
    _exec: Callback<T...>,
    _args: ArgPack?,
    Connected: boolean,
    Once: boolean, Yield: boolean, Safe: boolean,
    Disconnect: (self: Connection<T...>) -> (nil)
}
export type Signal<T...> = typeof(setmetatable({}, signal)) & {
    Name : string,
    Safe : boolean,
    _head : {
        _last: any,
        _next: any
    }
}

-- threads
local threads = {}
local free: thread?
local execute = function(thread, ref, exec, ...): nil
    if ref == threads then -- prevents external resumptions
        free = nil
        exec(...)
        free = free and table.insert(threads, thread) or free or thread
    end
    return nil
end
local main = function()
    local thread = coroutine.running()
    while true do
        execute(thread, coroutine.yield())
    end
    return nil
end
local function getThread(): thread
    return free or table.remove(threads) or task.spawn(main)
end

local function disconnect<T...>(self: Connection<T...>): nil
    (self._last :: Connection<...any>)._next = self._next;
    (self._next or self)._last = self._last
    self.Connected = false
    return nil
end

function signal:Connect<T...>(exec: Callback<T...>, ...: any): Connection<T...>
    local conn = {
        _last = nil, _next = nil,
        _signal = self,
        _exec = exec,
        _args = if select('#', ...) ~= 0
                then table.pack(...) else nil,
        Connected = true,
        Once = false,
        Yield = true,
        Safe = self.Safe,
        Disconnect = disconnect
    }
    local head = self._head
    head._last._next = conn
    conn._last = head._last :: TYPE_ERROR
    head._last = conn :: TYPE_ERROR
    return conn :: TYPE_ERROR
end

function signal:Once<T...>(exec: Callback<T...>, ...: any): Connection<T...>
    local conn = self:Connect(exec, ...)
    conn.Once = true
    return conn
end

function signal:ConnectWith<T...>(exec: Callback<T...>, mods: CMods?, ...: any): Connection<T...>
    local conn = self:Connect(exec, ...)
    if mods then
        conn.Once = if mods.once ~= nil
            then mods.once else conn.Once
        conn.Yield = if mods.noyield ~= nil
            then not mods.noyield else conn.Once
        conn.Safe = if mods.unsafe ~= nil
            then not mods.unsafe else conn.Safe
    end
    return conn
end

function signal:Wait<T...>(): (T...)
    self:Once(task.spawn, coroutine.running())
    return coroutine.yield()
end

function signal:Timeout<T...>(seconds: number?): (boolean, T...)
    local parent = coroutine.running()
    local conn = nil
    local timer = task.delay(seconds, function()
        conn:Disconnect()
        task.spawn(parent, false)
    end)
    conn = self:Once(function(...)
        task.cancel(timer)
        task.spawn(parent, true, ...)
    end)
    return coroutine.yield()
end

function signal:Fire<T...>(...: T...): nil
    local node = self._head._next
    if node then
        local safe = self.Safe
        local argc = select('#', ...)
        local argv: ArgPack, pack: ArgPack
        while node do
            if not node._args then
                if node.Yield then
                    if safe or node.Safe then
                        task.spawn(getThread(), threads, node._exec, ...)
                    else
                        coroutine.resume(getThread(), threads, node._exec, ...)
                    end
                else
                    node._exec(...)
                end
            else
                pack = node._args
                if argc > 0 then
                    argv = argv or table.pack(...)
                    pack = table.move(argv, 1, argv.n, pack.n + 1, table.clone(pack)) :: any
                    pack.n += argv.n
                end
                if node.Yield then
                    if safe or node.Safe then
                        task.spawn(getThread(), threads, node._exec, table.unpack(pack, 1, pack.n))
                    else
                        coroutine.resume(getThread(), threads, node._exec, table.unpack(pack, 1, pack.n))
                    end
                else
                    node._exec(table.unpack(pack, 1, pack.n))
                end
            end
            if node.Once then
                node:Disconnect()
            end

            node = node._next
        end
    end
    return nil
end

function signal:Clear<T...>(): nil
    self._head._next = nil
    self._head._last = self._head
    return nil
end

return function<T...>(name: string?): Signal<T...>
    local self = {
        Name = name or "Signal",
        Safe = true,
        _head = {
            _last = nil :: any,
            _next = nil :: any
        }
    }
    self._head._last = self._head
    return setmetatable(self, signal) :: TYPE_ERROR -- best fix to nonsensical typechecking errors ;)
end
