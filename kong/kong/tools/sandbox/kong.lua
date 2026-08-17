local clone = require "table.clone"


local setmetatable = setmetatable
local rawset = rawset
local unpack = table.unpack
local assert = assert
local error = error
local pairs = pairs
local pcall = pcall
local type = type
local load = load
local pack = table.pack


local function get_lua_env()
  return require("kong.tools.sandbox.environment").lua
end


local function get_schema_env()
  return require("kong.tools.sandbox.environment").schema
end


local function get_handler_env()
  return require("kong.tools.sandbox.environment").handler
end


local function create_lua_env(env)
  local new_env = clone(get_lua_env())
  if env then
    for k, v in pairs(new_env) do
      rawset(new_env, k, env[k] ~= nil and env[k] or v)
    end
    if env.require ~= nil then
      rawset(new_env, "require", env.require)
    end
    setmetatable(new_env, { __index = env })
  end
  return new_env
end


local function wrap(compiled)
  return function(...)
    local t = pack(pcall(compiled, ...))
    if not t[1] then
      return error(t[2], -1)
    end
    return unpack(t, 2, t.n)
  end
end


local function protect_backward_compatible(chunk, chunkname, mode, env)
  assert(type(chunk) == "string", "expected a string")
  local compiled, err = load(chunk, chunkname, mode or "t", create_lua_env(env))
  if not compiled then
    return error(err, -1)
  end
  local fn = wrap(compiled)
  return fn
end


local sandbox = {}


function sandbox.protect(chunk, chunkname_or_options, mode, env)
  if type(chunkname_or_options) == "table" then
    return protect_backward_compatible(chunk, nil, nil, chunkname_or_options and chunkname_or_options.env)
  end
  return protect_backward_compatible(chunk, chunkname_or_options, mode, env)
end


function sandbox.run(chunk, options, ...)
  return sandbox.protect(chunk, options)(...)
end


local function protect(chunk, chunkname, env)
  assert(type(chunk) == "string", "expected a string")
  local compiled, err = load(chunk, chunkname, "t", env)
  if not compiled then
    return error(err, -1)
  end
  return compiled
end


function sandbox.protect_lua(chunk, chunkname)
  return protect(chunk, chunkname, get_lua_env())
end


function sandbox.protect_schema(chunk, chunkname)
  return protect(chunk, chunkname, get_schema_env())
end


function sandbox.protect_handler(chunk, chunkname)
  return protect(chunk, chunkname, get_handler_env())
end


-- make sandbox(f) == sandbox.protect(f)
setmetatable(sandbox, {
  __call = function(_, chunk, chunkname_or_options, mode, env)
    return sandbox.protect(chunk, chunkname_or_options, mode, env)
  end
})


return sandbox
