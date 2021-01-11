local sandbox = {
  _VERSION      = "sandbox 0.5",
  _DESCRIPTION  = "A pure-lua solution for running untrusted Lua code.",
  _URL          = "https://github.com/kikito/sandbox.lua",
  _LICENSE      = [[
    MIT LICENSE

    Copyright (c) 2013 Enrique García Cota

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ]]
}

-- Lua 5.2, 5.3 and above
-- https://leafo.net/guides/setfenv-in-lua52-and-above.html#setfenv-implementation
local setfenv = setfenv or function(fn, env)
  local i = 1
  while true do
    local name = debug.getupvalue(fn, i)
    if name == "_ENV" then
      debug.upvaluejoin(fn, i, (function()
        return env
      end), 1)
      break
    elseif not name then
      break
    end

    i = i + 1
  end

  return fn
end

-- The base environment is merged with the given env option (or an empty table, if no env provided)
--
local BASE_ENV = {}

-- List of non-safe packages/functions:
--
-- * string.rep: can be used to allocate millions of bytes in 1 operation
-- * {set|get}metatable: can be used to modify the metatable of global objects (strings, integers)
-- * collectgarbage: can affect performance of other systems
-- * dofile: can access the server filesystem
-- * _G: It has access to everything. It can be mocked to other things though.
-- * load{file|string}: All unsafe because they can grant acces to global env
-- * raw{get|set|equal}: Potentially unsafe
-- * module|require|module: Can modify the host settings
-- * string.dump: Can display confidential server info (implementation of functions)
-- * string.rep: Can allocate millions of bytes in one go
-- * math.randomseed: Can affect the host sytem
-- * io.*, os.*: Most stuff there is non-save


-- Safe packages/functions below
local packages = [[

_VERSION assert error    ipairs   next pairs
pcall    select tonumber tostring type unpack xpcall

coroutine.create coroutine.resume coroutine.running coroutine.status
coroutine.wrap   coroutine.yield

math.abs   math.acos math.asin  math.atan math.atan2 math.ceil
math.cos   math.cosh math.deg   math.exp  math.fmod  math.floor
math.frexp math.huge math.ldexp math.log  math.log10 math.max
math.min   math.modf math.pi    math.pow  math.rad   math.random
math.sin   math.sinh math.sqrt  math.tan  math.tanh

os.clock os.difftime os.time

string.byte string.char  string.find  string.format string.gmatch
string.gsub string.len   string.lower string.match  string.reverse
string.sub  string.upper

table.insert table.maxn table.remove table.sort

]]

local protect_modules = 'coroutine math os string table'

packages:gsub('%S+', function(id)
  local module, method = id:match('([^%.]+)%.([^%.]+)')
  if module then
    BASE_ENV[module]         = BASE_ENV[module] or {}
    BASE_ENV[module][method] = _G[module][method]
  else
    BASE_ENV[id] = _G[id]
  end
end)

protect_modules:gsub('%S+', function(module)
  BASE_ENV[module] = setmetatable({}, {
    __index = BASE_ENV[module],
    __newindex = function() error("This table is read-only.") end
  })
end)

local string_rep = string.rep

-- Public interface: sandbox.protect
function sandbox.protect(f, options)
  options = options or {}

  local passed_env = options.env or {}
  local env = setmetatable({}, {
    __index = function(_, k)
      local v = BASE_ENV[k]
      if v == nil then
        return passed_env[k]
      end
      return v
    end,
  })

  env._G = env._G or env

  if type(f) == 'string' then
    f = assert(load(f, options.chunk_name, options.mode, env))
  else
    setfenv(f, env)
  end

  return function(...)

    string.rep = nil

    local t = table.pack(pcall(f, ...))

    string.rep = string_rep

    if not t[1] then error(t[2]) end

    return table.unpack(t, 2, t.n)
  end
end

-- Public interface: sandbox.run
function sandbox.run(f, options, ...)
  return sandbox.protect(f, options)(...)
end

-- make sandbox(f) == sandbox.protect(f)
setmetatable(sandbox, {__call = function(_,f,o) return sandbox.protect(f,o) end})

return sandbox
