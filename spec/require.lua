-- Bundled from https://github.com/pygy/require.lua
-- License MIT
--- usage:
-- require = require"require".require
-- :o)

local error, ipairs, newproxy, tostring, type
    = error, ipairs, newproxy, tostring, type

local t_concat = table.concat

--- Helpers


local function checkstring(s)
    local t = type(s)
    if t == "string" then
        return s
    elseif t == "number" then
        return tostring(s)
    else
        error("bad argument #1 to 'require' (string expected, got "..t..")", 3)
    end
end

--- for Lua 5.1

local package, p_loaded, setmetatable = package, package.loaded, setmetatable

local sentinel do
    local function errhandler() error("the require() sentinel can't be indexed or updated", 2) end
    sentinel = newproxy and newproxy() or setmetatable({}, {__index = errhandler, __newindex = errhandler, __metatable = false})
end

local function require51 (name)
    name = checkstring(name)
    if p_loaded[name] == sentinel then
        error("loop or previous error loading module '"..name.."'", 2)
    end

    local module = p_loaded[name]
    if module then return module end

    local msg = {}
    local loader
    for _, searcher in ipairs(package.loaders) do
        loader = searcher(name)
        if type(loader) == "function" then break end
        if type(loader) == "string" then
            -- `loader` is actually an error message
            msg[#msg + 1] = loader
        end
        loader = nil
    end
    if loader == nil then
        error("module '" .. name .. "' not found: "..t_concat(msg), 2)
    end
    p_loaded[name] = sentinel
    local res = loader(name)
    if res ~= nil then
        module = res
    elseif p_loaded[name] == sentinel or not p_loaded[name] then
        module = true
    else
	module = p_loaded[name]
    end

    p_loaded[name] = module
    return module
end

local module = {
    VERSION = "0.1.8",
    require51 = require51,
}

if _VERSION == "Lua 5.1" then module.require = require51 end

--- rerequire :o)

for _, o in ipairs{
    {"rerequiredefault", require},
    {"rerequire", module.require},
    {"rerequire51", require51},
} do
    local rereq, req = o[1], o[2]
    module[rereq] = function(name)
        p_loaded[name] = nil
        return req(name)
    end
end

return module
