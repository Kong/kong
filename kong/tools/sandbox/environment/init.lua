-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local ENVIRONMENT do
  ENVIRONMENT = {}

  local setmetatable = setmetatable
  local getmetatable = getmetatable
  local require = require
  local package = package
  local rawset = rawset
  local ipairs = ipairs
  local pairs = pairs
  local error = error
  local type = type
  local _G = _G

  local function wrap_method(self, method)
    return function(_, ...)
      return self[method](self, ...)
    end
  end

  local function include(env, id)
    -- The code here checks a lot of types and stuff, just to please our test suite
    -- to not error out when used with mocks.
    local m, sm, lf, f = id:match("([^%.]+)%.([^%.]+)%.([^%.]+)%.([^%.]+)")
    if m then
      env[m] = env[m] or {}
      env[m][sm] = env[m][sm] or {}
      env[m][sm][lf] = env[m][sm][lf] or {}

      if m == "kong" and sm == "db" then
        env[m][sm][lf][f] = type(_G[m]) == "table"
          and type(_G[m][sm]) == "table"
          and type(_G[m][sm][lf]) == "table"
          and type(_G[m][sm][lf][f]) == "function"
          and wrap_method(_G[m][sm][lf], f)
      else
        env[m][sm][lf][f] = type(_G[m]) == "table"
          and type(_G[m][sm]) == "table"
          and type(_G[m][sm][lf]) == "table"
          and _G[m][sm][lf][f]
      end

    else
      m, sm, f = id:match("([^%.]+)%.([^%.]+)%.([^%.]+)")
      if m then
        env[m] = env[m] or {}
        env[m][sm] = env[m][sm] or {}

        if m == "kong" and sm == "cache" then
          env[m][sm][f] = type(_G[m]) == "table"
            and type(_G[m][sm]) == "table"
            and type(_G[m][sm][f]) == "function"
            and wrap_method(_G[m][sm], f)

        else
          env[m][sm][f] = type(_G[m]) == "table"
            and type(_G[m][sm]) == "table"
            and _G[m][sm][f]
        end

      else
        m, f = id:match("([^%.]+)%.([^%.]+)")
        if m then
          env[m] = env[m] or {}
          env[m][f] = type(_G[m]) == "table" and _G[m][f]

        else
          env[id] = _G[id]
        end
      end
    end
  end


  local function protect_module(modname, mod)
    return setmetatable(mod, {
      __newindex = function(_, k, _)
        return error(("Cannot modify %s.%s. Protected by the sandbox."): format(modname, k), -1)
      end
    })
  end

  local function protect_modules(mod, modname)
    for k, v in pairs(mod) do
      if type(v) == "table" then
        protect_modules(v, modname and (modname .. "." .. k) or k)
      end
    end

    if modname and modname ~= "ngx" then
      protect_module(modname, mod)
    end
  end

  local function protect(env)
    protect_modules(env, "_G")
    rawset(env, "_G", env)

    local kong = kong
    local ngx = ngx

    if type(ngx) == "table" and type(env.ngx) == "table" then
      -- this is needed for special ngx.{ctx|headers_sent|is_subrequest|status)
      setmetatable(env.ngx, getmetatable(ngx))

      -- libraries having metatable logic
      rawset(env.ngx, "var", ngx.var)
      rawset(env.ngx, "arg", ngx.arg)
      rawset(env.ngx, "header", ngx.header)
    end

    if type(kong) == "table" and type(env.kong) == "table" then
      -- __call meta-method for kong log
      if type(kong.log) == "table" and type(env.kong.log) == "table" then
        getmetatable(env.kong.log).__call = (getmetatable(kong.log) or {}).__call

        if type(kong.log.inspect) == "table" and type(env.kong.log.inspect) == "table" then
          getmetatable(env.kong.log.inspect).__call = (getmetatable(kong.log.inspect) or {}).__call
        end
        if type(kong.log.deprecation) == "table" and type(env.kong.log.deprecation) == "table" then
          getmetatable(env.kong.log.deprecation).__call = (getmetatable(kong.log.deprecation) or {}).__call
        end
      end

      if type(kong.configuration) == "table" and type(kong.configuration.remove_sensitive) == "function" then
        -- only expose the non-sensitive parts of kong.configuration
        rawset(env.kong, "configuration",
               protect_module("kong.configuration", kong.configuration.remove_sensitive()))
      end

      if type(kong.ctx) == "table" then
        -- only support kong.ctx.shared and kong.ctx.plugin
        local ctx = kong.ctx
        rawset(env.kong, "ctx", protect_module("kong.ctx", {
          shared = setmetatable({}, {
            __newindex = function(_, k, v)
              ctx.shared[k] = v
            end,
            __index = function(_, k)
              return ctx.shared[k]
            end,
          }),
          plugin = setmetatable({}, {
            __newindex = function(_, k, v)
              ctx.plugin[k] = v
            end,
            __index = function(_, k)
              return ctx.plugin[k]
            end,
          })
        }))
      end
    end

    return env
  end

  local sandbox_require = require("kong.tools.sandbox.require")

  -- the order is from the biggest to the smallest so that package
  -- unloading works properly (just to not leave garbage around)
  for _, t in ipairs({ "handler", "schema", "lua" }) do
    local env = {}
    local package_name = "kong.tools.sandbox.environment." .. t
    require(package_name):gsub("%S+", function(id)
      include(env, id)
    end)
    package.loaded[package_name] = nil
    rawset(env, "require", sandbox_require[t])
    ENVIRONMENT[t] = protect(env)
  end

  package.loaded["kong.tools.sandbox.require"] = nil
end


return ENVIRONMENT
