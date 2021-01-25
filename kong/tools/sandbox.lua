local _sandbox = require "sandbox"

local table = table
local fmt = string.format
local setmetatable = setmetatable
local require = require
local ipairs = ipairs
local pcall = pcall
local type = type
local error = error
local rawset = rawset
local assert = assert
local kong = kong


-- deep copy tables using dot notation, like
-- one: { foo = { bar = { hello = {}, ..., baz = 42 } } }
-- target: { hey = { "hello } }
-- link("foo.bar.baz", one, target)
-- target -> { hey = { "hello" }, foo = { bar = { baz = 42 } } }
local function link(q, o, target)
  if not q then return end

  local h, r = q:match("([^%.]+)%.?(.*)")
  local mod = o[h]

  if not mod then return end

  if r == "" then
    if type(mod) == 'table' then
      -- changes on target[h] won't affect mod
      target[h] = setmetatable({}, { __index = mod })

    else
      target[h] = mod
    end

    return
  end

  if not target[h] then target[h] = {} end

  link(r, o[h], target[h])
end


local lazy_conf_methods = {
  enabled = function(self)
    return kong and
           kong.configuration and
           kong.configuration.untrusted_lua and
           kong.configuration.untrusted_lua ~= 'off'
  end,
  sandbox_enabled = function(self)
    return kong and
           kong.configuration and
           kong.configuration.untrusted_lua and
           kong.configuration.untrusted_lua == 'sandbox'
  end,
  requires = function(self)
    local conf_r = kong and
                   kong.configuration and
                   kong.configuration.untrusted_lua_sandbox_requires or {}
    local requires = {}
    for _, r in ipairs(conf_r) do requires[r] = true end
    return requires
  end,
  env_vars = function(self)
    return kong and
           kong.configuration and
           kong.configuration.untrusted_lua_sandbox_environment or {}
  end,
  environment = function(self)
    local env = {
        -- home brewed require function that only requires what we consider
        -- safe :)
        ["require"] = function(m)
          if not self.requires[m] then
            error(fmt("require '%s' not allowed within sandbox", m))
          end

          return require(m)
        end,
    }

    for _, m in ipairs(self.env_vars) do link(m, _G, env) end

    return env
  end,
}


local conf_values = {
  clear = table.clear,
  reload = table.clear,
  err_msg = "loading of untrusted Lua code disabled because " ..
            "'untrusted_lua' config option is set to 'off'"
}


local configuration = setmetatable({}, {
  __index = function(self, key)
    local l = lazy_conf_methods[key]

    if not l then
      return conf_values[key]
    end

    local value = l(self)
    rawset(self, key, value)

    return value
  end,
})


local sandbox = function(fn, opts)
  if not configuration.enabled then
    error(configuration.err_msg)
  end

  opts = opts or {}

  local opts = {
    -- default set load string mode to only 'text chunks'
    mode = opts.mode or 't',
    env = opts.env or {},
    chunk_name = opts.chunk_name,
  }

  if not configuration.sandbox_enabled then
    -- sandbox disabled, all arbitrary Lua code can execute unrestricted
    setmetatable(opts.env, { __index = _G})

    return assert(load(fn, opts.chunk_name, opts.mode, opts.env))
  end

  -- set (discard-able) function context
  setmetatable(opts.env, { __index = configuration.environment })

  return _sandbox(fn, opts)
end


local function validate_function(fun, opts)
  local ok, func1 = pcall(sandbox, fun, opts)
  if not ok then
    return false, "Error parsing function: " .. func1
  end

  local success, func2 = pcall(func1)

  if not success then
    return false, func2
  end

  if type(func2) == "function" then
    return func2
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got "
                .. type(func2)
end


local function parse(fn_str, opts)
  return assert(validate_function(fn_str, opts))
end


local _M = {}


_M.validate_function = validate_function


_M.validate = function(fn_str, opts)
  local _, err = validate_function(fn_str, opts)
  if err then return false, err end

  return true
end


-- meant for schema, do not execute arbitrary lua!
-- https://github.com/Kong/kong/issues/5110
_M.validate_safe = function(fn_str, opts)
  local ok, func1 = pcall(sandbox, fn_str, opts)

  if not ok then
    return false, "Error parsing function: " .. func1
  end

  return true
end


_M.sandbox = sandbox
_M.parse = parse
-- useful for testing
_M.configuration = configuration


return _M
