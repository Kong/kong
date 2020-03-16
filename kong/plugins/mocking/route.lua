local require      = require
local router       = require "resty.route.router"
local setmetatable = setmetatable
local getmetatable = getmetatable
local reverse      = string.reverse
local create       = coroutine.create
local select       = select
local dofile       = dofile
local assert       = assert
local error        = error
local concat       = table.concat
local unpack       = table.unpack or unpack
local ipairs       = ipairs
local pairs        = pairs
local lower        = string.lower
local floor        = math.floor
local pcall        = pcall
local type         = type
local find         = string.find
local byte         = string.byte
local max          = math.max
local sub          = string.sub
local var          = ngx.var
local S            = byte "*"
local H            = byte "#"
local E            = byte "="
local T            = byte "~"
local F            = byte "/"
local A            = byte "@"
local lfs
do
    local o, l = pcall(require, "syscall.lfs")
    if not o then o, l = pcall(require, "lfs") end
    if o then lfs = l end
end
local matchers = {
    prefix  = require "resty.route.matchers.prefix",
    equals  = require "resty.route.matchers.equals",
    match   = require "resty.route.matchers.match",
    regex   = require "resty.route.matchers.regex",
    simple  = require "resty.route.matchers.simple",
}
local selectors = {
    [E] = matchers.equals,
    [H] = matchers.match,
    [T] = matchers.regex,
    [A] = matchers.simple
}
local http = require "resty.route.handlers.http"
local handlers = {
    -- Common
    delete      = http,
    get         = http,
    head        = http,
    post        = http,
    put         = http,
    -- Pathological
    connect     = http,
    options     = http,
    trace       = http,
    -- WebDAV
    copy        = http,
    lock        = http,
    mkcol       = http,
    move        = http,
    propfind    = http,
    proppatch   = http,
    search      = http,
    unlock      = http,
    bind        = http,
    rebind      = http,
    unbind      = http,
    acl         = http,
    -- Subversion
    report      = http,
    mkactivity  = http,
    checkout    = http,
    merge       = http,
    -- UPnP
    msearch     = http,
    notify      = http,
    subscribe   = http,
    unsubscribe = http,
    -- RFC5789
    patch       = http,
    purge       = http,
    -- CalDAV
    mkcalendar  = http,
    -- RFC2068
    link        = http,
    unlink      = http,
    -- Special
    sse         = require "resty.route.handlers.sse",
    websocket   = require "resty.route.handlers.websocket"
}
local function location(l)
    return l or var.uri
end
local function method(m)
    local t = type(m)
    if t == "string" then
        local h = lower(m)
        return handlers[h] and h or m
    elseif var.http_accept == "text/event-stream" then
        return "sse"
    elseif var.http_upgrade == "websocket" then
        return "websocket"
    else
        return lower(var.request_method)
    end
end
local function array(t)
    if type(t) ~= "table" then return false end
    local m, c = 0, 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 0 or floor(k) ~= k then return false end
        m = max(m, k)
        c = c + 1
    end
    return c == m
end
local function callable(f)
    if type(f) == "function" then
        return true
    end
    local m = getmetatable(f)
    return m and type(m.__call) == "function"
end
local function methods(m)
    local t = type(m)
    if t == "table" and array(m) and #m > 0 then
        for _, n in ipairs(m) do
            if not handlers[n] then
                return false
            end
        end
        return true
    elseif t == "string" then
        return not not handlers[m]
    end
    return false
end
local function routing(p)
    local t = type(p)
    if t == "table" and array(p) and #p > 0 then
        for _, q in ipairs(p) do
            if type(q) ~= "string" then
                return false
            end
            local b = byte(q)
            if not selectors[b] and S ~= b and F ~= b then
                return false
            end
        end
        return true
    elseif t == "string" then
        local b = byte(p)
        return selectors[b] or S == b or F == b
    else
        return false
    end
end
local function resolve(p)
    local b = byte(p)
    if b == S then return matchers.prefix, sub(p, 2), true end
    local s = selectors[b]
    if s then
        if b == H or byte(p, 2) ~= S then return s, sub(p, 2) end
        return s, sub(p, 3), true
    end
    return matchers.prefix, p
end
local function named(self, i, c, f)
    local l = self[i]
    if f then
        local t = type(f)
        if t == "function" then
            l[c] = f
        elseif t == "table" then
            if callable[f[c]] then
                l[c] = f[c]
            elseif callable(f) then
                l[c] = f
            else
                error "Invalid handler"
            end
        else
            error "Invalid handler"
        end
    else
        local t = type(c)
        if t == "function" then
            l[-1] = c
        elseif t == "table" then
            for n, x in pairs(c) do
                if callable(x) then
                    l[n] = x
                end
            end
            if callable(c) then
                l[-1] = c
            end
        else
            return function(x)
                return named(self, i, c, x)
            end
        end
    end
    return self
end
local function matcher(h, ...)
    if select(1, ...) then
        return create(h), ...
    end
end
local function locator(l, m, p, f)
    local n = l.n + 1
    l.n = n
    if m then
        if p then
            local match, pattern, insensitive = resolve(p)
            l[n] = function(request_method, request_location)
                if m == request_method then
                    return matcher(f, match(request_location, pattern, insensitive))
                end
            end
        else
            l[n] = function(request_method)
                if m == request_method then
                    return create(f)
                end
            end
        end
    elseif p then
        local match, pattern, insensitive = resolve(p)
        l[n] = function(_, request_location)
            return matcher(f, match(request_location, pattern, insensitive))
        end
    else
        l[n] = function()
            return create(f)
        end
    end
    return true
end
local function append(l, m, p, f)
    local o
    local mt = type(m)
    local pt = type(p)
    if mt == "table" and pt == "table" then
        for _, a in ipairs(m) do
            for _, b in ipairs(p) do
                local c = handlers[a](f)
                if type(c) == "function" then
                    o = locator(l, a, b, c)
                end
            end
        end
    elseif mt == "table" then
        for _, a in ipairs(m) do
            local b = handlers[a](f)
            if type(b) == "function" then
                o = locator(l, a, p, b)
            end
        end
    elseif pt == "table" then
        for _, a in ipairs(p) do
            if m then
                local b = handlers[m](f)
                if type(b) == "function" then
                    o = locator(l, m, a, b)
                end
            else
                o = locator(l, nil, a, f)
            end
        end
    else
        if m then
            local a = handlers[m](f)
            if type(a) == "function" then
                o = locator(l, m, p, a)
            end
        else
            o = locator(l, m, p, f)
        end
    end
    return o
end
local function call(self, ...)
    local n = select("#", ...)
    assert(n == 1 or n == 2 or n == 3, "Invalid number of arguments")
    if n == 3 then
        local m, p, f, o = ...
        local l = not self.filter and p and self[1] or self[2]
        assert(m == nil or methods(m), "Invalid method")
        assert(p == nil or routing(p), "Invalid pattern")
        f = l[f] or f
        local t = type(f)
        if t == "function" then
            o = append(l, m, p, f)
        elseif t == "table" then
            if m and p then
                o = append(l, m, p, f)
            elseif m then
                for x, r in pairs(f) do
                    if routing(x) then
                        o = self(m, x, r)
                    end
                end
                o = append(l, m, p, f) or o
            elseif p then
                for x, r in pairs(f) do
                    if methods(x) then
                        o = self(x, p, r) or o
                    end
                end
            else
                for x, r in pairs(f) do
                    if methods(x) then
                        o = self(x, nil, r) or o
                    elseif routing(x) then
                        o = self(nil, x,  r) or o
                    end
                end
            end
            if callable(f) then
                o = append(l, m, p, f) or o
            end
        elseif t == "string" then
            o, f = pcall(require, f)
            assert(o, f)
            o = self(m, p, f) and true
        end
        if o then
            return self
        end
        error "Invalid function"
    elseif n == 2 then
        local m, p = ...
        if methods(m) then
            if routing(p) then
                return function(...)
                    return self(m, p, ...)
                end
            else
                return self(m, nil, p)
            end
        elseif routing(m) then
            return self(nil, ...)
        elseif routing(p) then
            assert(m == nil, "Invalid method")
            return function(...)
                return self(nil, p, ...)
            end
        else
            assert(m == nil, "Invalid method")
            assert(p == nil, "Invalid pattern")
            return function(...)
                return self(nil, nil, ...)
            end
        end
    elseif n == 1 then
        local m = ...
        if methods(m) then
            return function(...)
                return self(m, ...)
            end
        elseif routing(m) then
            return self(nil, ...)
        else
            return self(nil, nil, ...)
        end
    end
end
local filter = {}
filter.__index = filter
filter.__call = call
function filter.new(...)
    return setmetatable({ ... }, filter)
end
local route = {}
route.__index = route
route.__call = call
function route.new()
    local a, b = { n = 0 }, { n = 0 }
    return setmetatable({ {}, { n = 0 }, a, b, filter = filter.new(a, b) }, route)
end
function route:match(l, p)
    local m, q, i = resolve(p)
    return m(l, q, i)
end
function route:clean(l)
    if type(l) ~= "string" or l == "" or l == "/" or l == "." or l == ".." then return "/" end
    local s = find(l, "/", 1, true)
    if not s then return "/" .. l end
    local i, n, t = 1, 1, {}
    while s do
        if i < s then
            local f = sub(l, i, s - 1)
            if f == ".." then
                n = n > 1 and n - 1 or 1
                t[n] = nil
            elseif f ~= "." then
                t[n] = f
                n = n + 1
            end
        end
        i = s + 1
        s = find(l, "/", i, true)
    end
    local f = sub(l, i)
    if f == ".." then
        n = n > 1 and n - 1 or 1
        t[n] = nil
    elseif f ~= "." then
        t[n] = f
    end
    return "/" .. concat(t, "/")
end
function route:use(...)
    return self.filter(...)
end
function route:fs(p, l)
    assert(lfs, "Lua file system (LFS) library was not found")
    p = p or var.document_root
    if not p then return end
    if byte(p, -1) == F then
        p = sub(p, 1, #p - 1)
    end
    l = l or ""
    if byte(l) == F then
        l = sub(l, 2)
    end
    if byte(l, -1) == F then
        l = sub(l, 1, #l - 1)
    end
    local dir = lfs.dir
    local attributes = lfs.attributes
    local dirs = { n = 0 }
    for file in dir(p) do
        if file ~= "." and file ~= ".." then
            local f = concat{ p, "/", file}
            local mode = attributes(f).mode
            if mode == "directory" then
                local x = { l, "/" }
                x[3] = file == "#" and ":number" or file
                dirs.n = dirs.n + 1
                dirs[dirs.n] = { f, concat(x) }
            elseif (mode == "file" or mode == "link") and sub(file, -4) == ".lua" then
                local b = sub(file, 1, #file - 4)
                local m
                local i = find(reverse(b), "@", 1, true)
                if i then
                    m = sub(b, -i+1)
                    b = sub(b, 1, -i-1)
                end
                local x = { "@*/" }
                if l ~= "" then
                    x[2] = l
                    if b ~= "index" then
                        if b == "#" then
                            x[3] = "/:number"
                        else
                            x[3] = "/"
                            x[4] = b
                        end
                    end
                else
                    if b ~= "index" then
                        if b == "#" then
                            x[2] = ":number"
                        else
                            x[2] = b
                        end
                    end
                end
                f = dofile(f)
                self(m, concat(x), f)
            end
        end
    end
    for i=1, dirs.n do
        self:fs(dirs[i][1], dirs[i][2])
    end
    return self
end
function route:on(...)
    return named(self, 1, ...)
end
function route:as(...)
    return named(self, 2, ...)
end
function route:dispatch(l, m)
    router.new(unpack(self)):to(location(l), method(m))
end
for h in pairs(handlers) do
    local f = function(self, ...)
        return self(h, ...)
    end
     route[h] = f
    filter[h] = f
end
return route
