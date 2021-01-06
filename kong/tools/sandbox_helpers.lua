-- XXX Use sandbox.lua once it gets published
-- https://github.com/kikito/sandbox.lua/pull/2
local _sandbox = require "kong.tools.sandbox"

local utils = require "kong.tools.utils"

local fmt = string.format
local unpack = unpack or table.unpack
local split = utils.split


local configuration = setmetatable({
  -- useful method for specs
  reload = function(self)
    local r = self.reload
    for k in next, self do rawset(self, k, nil) end
    rawset(self, "reload", r)
  end,
}, {
  __index = function(self, key)
    local function link(q, o, target)
      if not q then return end

      local h, r = unpack(split(q, '.', 2))
      local mod = o[h]

      if not mod then return end

      if not r then
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

    local methods = {
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
            require = function(m)
              if not self.requires[m] then
                error(fmt("require \'%s\' not allowed within sandbox", m))
              end
              return require(m)
            end,
        }

        for _, m in ipairs(self.env_vars) do link(m, _G, env) end

        return env
      end,
      err_msg = function(self)
        return "untrusted lua code not allowed by KONG_UNTRUSTED_LUA = 'off'"
      end,
    }

    local l = methods[key]

    if not l then return end

    local value = l(self)
    rawset(self, key, value)

    return value
  end,
})


local sandbox = function(fn, opts)
  if not configuration.enabled then
    error(configuration.err_msg)
    -- or even
    -- return function(...)
    --   kong.log.error("some error on the logs") return ...
    -- end
  end

  opts = opts or {}

  local opts = {
    -- defaut set load string mode to only 'text chunks'
    mode = opts.mode or 't',
    env = opts.env or {},
    chunk_name = opts.chunk_name,
  }

  if not configuration.sandbox_enabled then
    -- sandbox disabled, all arbitrary lua code belongs to us
    setmetatable(opts.env, { __index = _G})
    local fn, err = load(fn, opts.chunk_name, opts.mode, opts.env)
    if err then error(err) end

    return fn
  end

  -- set (discardable) function context
  setmetatable(opts.env, { __index = configuration.environment })

  return _sandbox(fn, opts)
end


local function validate_function(fun, opts)
  local ok, func1 = pcall(sandbox, fun, opts)
  if not ok then
    return false, "Error parsing function: " .. func1
  end

  local success, func2 = pcall(func1)

  if success and type(func2) == "function" then
    return func2
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got "
                .. type(func2)
end


local function parse(fn_str, opts)
  local fn, err = validate_function(fn_str, opts)
  if not fn then error(err) end

  return fn
end


local _M = {}

_M.validate_function = validate_function

_M.validate = function(fn_str, opts)
  local _, err = _M.validate_function(fn_str, opts)
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
