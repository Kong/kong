--- Current request context data
--
-- @module kong.ctx


local ngx = ngx


-- shared between all global instances
local _CTX_SHARED_KEY = {}
local _CTX_CORE_KEY = {}


---
-- A table that has the lifetime of the current request and is shared between
-- all plugins. It can be used to share data between several plugins in a given
-- request.
--
-- Since only relevant in the context of a request, this table cannot be
-- accessed from the top-level chunk of Lua modules. Instead, it can only be
-- accessed in request phases, which are represented by the `rewrite`,
-- `access`, `header_filter`, `body_filter`, `log`, and `preread` phases of
-- the plugin interfaces. Accessing this table in those functions (and their
-- callees) is fine.
--
-- Values inserted in this table by a plugin will be visible by all other
-- plugins.  One must use caution when interacting with its values, as a naming
-- conflict could result in the overwrite of data.
--
-- @table kong.ctx.shared
-- @phases rewrite, access, header_filter, body_filter, log, preread
-- @usage
-- -- Two plugins A and B, and if plugin A has a higher priority than B's
-- -- (it executes before B):
--
-- -- plugin A handler.lua
-- function plugin_a_handler:access(conf)
--   kong.ctx.shared.foo = "hello world"
--
--   kong.ctx.shared.tab = {
--     bar = "baz"
--   }
-- end
--
-- -- plugin B handler.lua
-- function plugin_b_handler:access(conf)
--   kong.log(kong.ctx.shared.foo) -- "hello world"
--   kong.log(kong.ctx.shared.tab.bar) -- "baz"
-- end


---
-- A table that has the lifetime of the current request - Unlike
-- `kong.ctx.shared`, this table is **not** shared between plugins. Instead,
-- it is only visible for the current plugin.
--
-- Because of its namespaced nature, this table is safer for a plugin to use
-- than `kong.ctx.shared` since it avoids potential naming conflicts, which
-- could lead to different plugins unknowingly overwrite each other's data.
--
-- Since only relevant in the context of a request, this table cannot be
-- accessed from the top-level chunk of Lua modules. Instead, it can only be
-- accessed in request phases, which are represented by the `rewrite`,
-- `access`, `header_filter`, `body_filter`, `log`, and `preread` phases
-- of the plugin interfaces. Accessing this table in those functions (and
-- their callees) is fine.
--
-- Values inserted in this table by a plugin will be visible in succeeding
-- phases (please note that the plugin configuration, that is passed to phase
-- handler function, may change between the phases of the request).
-- The following example illustrates how a plugin can save a value on access
-- phase for post-processing on log phase:
--
-- @table kong.ctx.plugin
-- @phases rewrite, access, header_filter, body_filter, log, preread
-- @usage
-- -- plugin handler.lua
--
-- function plugin_handler:access(conf)
--   kong.ctx.plugin.val_1 = "hello"
--   kong.ctx.plugin.val_2 = "world"
-- end
--
-- function plugin_handler:log(conf)
--   local value = kong.ctx.plugin.val_1 .. " " .. kong.ctx.plugin.val_2
--
--   kong.log(value) -- "hello world"
-- end
local function new(self)
  local _CTX = {
    -- those would be visible on the *.ctx namespace for now
    -- TODO: hide them in a private table shared between this
    -- module and the global.lua one
    keys = setmetatable({}, { __mode = "v" }),
  }


  local _ctx_mt = {}


  function _ctx_mt.__index(t, k)
    local nctx = ngx.ctx
    local key

    if k == "core" then
      key = _CTX_CORE_KEY

    elseif k == "shared" then
      key = _CTX_SHARED_KEY

    else
      key = t.keys[k]
    end

    if key then
      local ctx = nctx[key]
      if not ctx then
        ctx = {}
        nctx[key] = ctx
      end

      return ctx
    end
  end


  return setmetatable(_CTX, _ctx_mt)
end


return {
  new = new,
}
