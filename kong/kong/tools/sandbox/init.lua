local sb_kong = require("kong.tools.sandbox.kong")


local table = table
local setmetatable = setmetatable
local require = require
local ipairs = ipairs
local pcall = pcall
local type = type
local load = load
local error = error
local rawset = rawset
local assert = assert


-- deep copy tables using dot notation, like
-- one: { foo = { bar = { hello = {}, ..., baz = 42 } } }
-- target: { hey = { "hello } }
-- link("foo.bar.baz", one, target)
-- target -> { hey = { "hello" }, foo = { bar = { baz = 42 } } }
local function link(q, o, target)
  if not q then
    return
  end

  local h, r = q:match("([^%.]+)%.?(.*)")

  local mod = o[h]
  if not mod then
    return
  end

  if r == "" then
    if type(mod) == "table" then
      -- changes on target[h] won't affect mod
      target[h] = setmetatable({}, { __index = mod })

    else
      target[h] = mod
    end

    return
  end

  if not target[h] then
    target[h] = {}
  end

  link(r, o[h], target[h])
end


local function get_conf(name)
  return kong
     and kong.configuration
     and kong.configuration[name]
end


local function link_vars(vars, env)
  if vars then
    for _, m in ipairs(vars) do
      link(m, _G, env)
    end
  end

  env._G = env

  return env
end


local function denied_table(modname)
  return setmetatable({}, { __index = {}, __newindex = function(_, k)
    return error(("Cannot modify %s.%s. Protected by the sandbox."):format(modname, k), -1)
  end, __tostring = function()
    return "nil"
  end })
end


local function denied_require(modname)
  return error(("require '%s' not allowed within sandbox"):format(modname), -1)
end


local function get_backward_compatible_sandboxed_kong()
  -- this is a more like a blacklist where we try to keep backwards
  -- compatibility, but still improve the default sandboxing not leaking
  -- secrets like pg_password.
  --
  -- just to note, kong.db.<entity>:truncate() and kong.db.connector:query(...)
  -- are quite powerful, but they are not disallowed for backwards compatibility.
  --
  -- of course this to work, the `getmetatable` and `require "inspect"` and such
  -- need to be disabled as well.

  local k
  if type(kong) == "table" then
    k = setmetatable({
      licensing = denied_table("kong.licensing"),
    }, { __index = kong })

    if type(kong.cache) == "table" then
      k.cache = setmetatable({
        cluster_events = denied_table("kong.cache.cluster_events")
      }, { __index = kong.cache })
    end

    if type(kong.core_cache) == "table" then
      k.core_cache = setmetatable({
        cluster_events = denied_table("kong.cache.cluster_events")
      }, { __index = kong.core_cache })
    end

    if type(kong.configuration) == "table" and type(kong.configuration.remove_sensitive) == "function" then
      k.configuration = kong.configuration.remove_sensitive()
    end

    if type(kong.db) == "table" then
      k.db = setmetatable({}, { __index = kong.db })
      if type(kong.db.connector) == "table" then
        k.db.connector = setmetatable({
          config = denied_table("kong.db.connector.config")
        }, { __index = kong.db.connector })
      end
    end
  end
  return k
end


local lazy_conf_methods = {
  enabled = function()
    return get_conf("untrusted_lua") ~= "off"
  end,
  sandbox_enabled = function()
    return get_conf("untrusted_lua") == "sandbox"
  end,
  requires = function()
    local sandbox_requires = get_conf("untrusted_lua_sandbox_requires")
    if type(sandbox_requires) ~= "table" or #sandbox_requires == 0 then
      return
    end
    local requires = {}
    for _, r in ipairs(sandbox_requires) do
      requires[r] = true
    end
    return requires
  end,
  env_vars = function()
    local env_vars = get_conf("untrusted_lua_sandbox_environment")
    if type(env_vars) ~= "table" or #env_vars == 0 then
      return
    end
    return env_vars
  end,
  environment = function(self)
    local requires = self.requires
    return link_vars(self.env_vars, requires and {
      -- home brewed require function that only requires what we consider safe :)
      require = function(modname)
        if not requires[modname] then
          return denied_require(modname)
        end
        return require(modname)
      end,
      -- allow almost full non-sandboxed access to everything in kong global
      kong = get_backward_compatible_sandboxed_kong(),
      -- allow full non-sandboxed access to everything in ngx global (including timers, :-()
      ngx = ngx,
    } or {
      require = denied_require,
      -- allow almost full non-sandboxed access to everything in kong global
      kong = get_backward_compatible_sandboxed_kong(),
      -- allow full non-sandboxed access to everything in ngx global (including timers, :-()
      ngx = ngx,
    })
  end,
  sandbox_mt = function(self)
    return { __index = self.environment }
  end,
  global_mt = function()
    return { __index = _G }
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


local function sandbox_backward_compatible(chunk, chunkname_or_options, mode, env)
  if not configuration.enabled then
    return error(configuration.err_msg, -1)
  end

  local chunkname
  if type(chunkname_or_options) == "table" then
    chunkname = chunkname_or_options.chunkname or chunkname_or_options.chunk_name
    mode = mode or chunkname_or_options.mode or "t"
    env = env or chunkname_or_options.env or {}
  else
    chunkname = chunkname_or_options
    mode = mode or "t"
    env = env or {}
  end

  if not configuration.sandbox_enabled then
    -- sandbox disabled, all arbitrary Lua code can execute unrestricted,
    -- but do not allow direct modification of the global environment
    return assert(load(chunk, chunkname, mode, setmetatable(env, configuration.global_mt)))
  end

  return sb_kong(chunk, chunkname, mode, setmetatable(env, configuration.sandbox_mt))
end


local function sandbox(chunk, chunkname, func)
  if not configuration.enabled then
    return error(configuration.err_msg, -1)
  end

  if not configuration.sandbox_enabled then
    -- sandbox disabled, all arbitrary Lua code can execute unrestricted,
    -- but do not allow direct modification of the global environment
    return assert(load(chunk, chunkname, "t", setmetatable({}, configuration.global_mt)))
  end

  return func(chunk, chunkname)
end


local function sandbox_lua(chunk, chunkname)
  return sandbox(chunk, chunkname, sb_kong.protect_lua)
end


local function sandbox_schema(chunk, chunkname)
  return sandbox(chunk, chunkname, sb_kong.protect_schema)
end


local function sandbox_handler(chunk, chunkname)
  return sandbox(chunk, chunkname, sb_kong.protect_handler)
end


local function validate_function(chunk, chunkname_or_options, mode, env)
  local ok, compiled_chunk = pcall(sandbox_backward_compatible, chunk, chunkname_or_options, mode, env)
  if not ok then
    return false, "Error parsing function: " .. compiled_chunk
  end

  local success, fn = pcall(compiled_chunk)
  if not success then
    return false, fn
  end

  if type(fn) == "function" then
    return fn
  end

  -- the code returned something unknown
  return false, "Bad return value from function, expected function type, got " .. type(fn)
end


local function parse(chunk, chunkname_or_options, mode, env)
  return assert(validate_function(chunk, chunkname_or_options, mode, env))
end


local function validate(chunk, chunkname_or_options, mode, env)
  local _, err = validate_function(chunk, chunkname_or_options, mode, env)
  if err then
    return false, err
  end

  return true
end


-- meant for schema, do not execute arbitrary lua!
-- https://github.com/Kong/kong/issues/5110
local function validate_safe(chunk, chunkname_or_options, mode, env)
  local ok, fn = pcall(sandbox_backward_compatible, chunk, chunkname_or_options, mode, env)
  if not ok then
    return false, "Error parsing function: " .. fn
  end

  return true
end


return {
  validate = validate,
  validate_safe = validate_safe,
  validate_function = validate_function,
  sandbox = sandbox_backward_compatible,
  sandbox_lua = sandbox_lua,
  sandbox_schema = sandbox_schema,
  sandbox_handler = sandbox_handler,
  parse = parse,
  --useful for testing
  configuration = configuration,
}
