local get_request = require "resty.core.base".get_request

local ngx           = ngx
local type          = type
local pcall         = pcall
local select        = select
local ipairs        = ipairs
local assert        = assert
local ngx_log       = ngx.log
local ngx_WARN      = ngx.WARN
local ngx_get_phase = ngx.get_phase


local _M = {}


local NON_FUNCTION_HOOKS = {
--[[
  [group_name] = {
    [hook_name] = <function>,
    ...
  },
  ...
--]]
}


local ALWAYS_ENABLED_GROUPS = {}


local function should_execute_original_func(group_name)
  if ALWAYS_ENABLED_GROUPS[group_name] then
    return
  end

  local phase = ngx_get_phase()
  if phase == "init" or phase == "init_worker" then
    return true
  end

  local dynamic_hook = ngx.ctx.dynamic_hook
  if not dynamic_hook then
    return true
  end

  local enabled_groups = dynamic_hook.enabled_groups
  if not enabled_groups[group_name] then
    return true
  end
end


local function execute_hook_vararg(hook, hook_type, group_name, ...)
  if not hook then
    return
  end

  local ok, err = pcall(hook, ...)
  if not ok then
    ngx_log(ngx_WARN, "failed to run ", hook_type, " hook of ", group_name, ": ", err)
  end
end


local function execute_hooks_vararg(hooks, hook_type, group_name, ...)
  if not hooks then
    return
  end

  for _, hook in ipairs(hooks) do
    execute_hook_vararg(hook, hook_type, group_name, ...)
  end
end


local function execute_after_hooks_vararg(handlers, group_name, ...)
  execute_hooks_vararg(handlers.afters, "after", group_name, ...)
  return ...
end


local function wrap_function_vararg(group_name, original_func, handlers)
  return function (...)
    if should_execute_original_func(group_name) then
      return original_func(...)
    end

    execute_hooks_vararg(handlers.befores, "before", group_name, ...)
    return execute_after_hooks_vararg(handlers, group_name, original_func(...))
  end
end


local function execute_hook(hook, hook_type, group_name, a1, a2, a3, a4, a5, a6, a7, a8)
  if not hook then
    return
  end

  local ok, err = pcall(hook, a1, a2, a3, a4, a5, a6, a7, a8)
  if not ok then
    ngx_log(ngx_WARN, "failed to run ", hook_type, " hook of ", group_name, ": ", err)
  end
end


local function execute_hooks(hooks, hook_type, group_name, a1, a2, a3, a4, a5, a6, a7, a8)
  if not hooks then
    return
  end

  for _, hook in ipairs(hooks) do
    execute_hook(hook, hook_type, group_name, a1, a2, a3, a4, a5, a6, a7, a8)
  end
end


local function execute_original_func(max_args, original_func, a1, a2, a3, a4, a5, a6, a7, a8)
  if max_args == 0 then
    return original_func()
  elseif max_args == 1 then
    return original_func(a1)
  elseif max_args == 2 then
    return original_func(a1, a2)
  elseif max_args == 3 then
    return original_func(a1, a2, a3)
  elseif max_args == 4 then
    return original_func(a1, a2, a3, a4)
  elseif max_args == 5 then
    return original_func(a1, a2, a3, a4, a5)
  elseif max_args == 6 then
    return original_func(a1, a2, a3, a4, a5, a6)
  elseif max_args == 7 then
    return original_func(a1, a2, a3, a4, a5, a6, a7)
  else
    return original_func(a1, a2, a3, a4, a5, a6, a7, a8)
  end
end


local function wrap_function(max_args, group_name, original_func, handlers)
  return function(a1, a2, a3, a4, a5, a6, a7, a8)
    local r1, r2, r3, r4, r5, r6, r7, r8

    if should_execute_original_func(group_name) then
      r1, r2, r3, r4, r5, r6, r7, r8 = execute_original_func(max_args, original_func, a1, a2, a3, a4, a5, a6, a7, a8)

    else
      execute_hooks(handlers.befores, "before", group_name, a1, a2, a3, a4, a5, a6, a7, a8)
      r1, r2, r3, r4, r5, r6, r7, r8 = execute_original_func(max_args, original_func, a1, a2, a3, a4, a5, a6, a7, a8)
      execute_hooks(handlers.afters, "after", group_name, r1, r2, r3, r4, r5, r6, r7, r8)
    end

    return r1, r2, r3, r4, r5, r6, r7, r8
  end
end


--- Hooks (patches) a function
-- Hooks "before" and "after" handlers to a function. The function is patched
-- to execute the handlers when it is called. The `parent` and `function_key`
-- parameters are used to identify and patch the function to be hooked.
--
-- @function dynamic_hook:hook_function
-- @tparam string group_name The name of the hook group
-- @tparam table parent The table containing the function to be hooked
-- @tparam string function_key The key (in the `parent` table) of the function
--         to be hooked
-- @tparam number max_args The maximum number of arguments the function accepts
-- @tparam table handlers A table containing the `before` and `after` handlers. 
--         The table may contain the keys listed below:
--           * table `befores` array of handlers to execute before the function
--           * table `afters` array of handlers to execute before the function
--
-- @usage
-- -- Define a "before" handler to be executed before the _G.print function
-- dynamic_hook.hook_function("my_group", _G, "print", "varargs", {
--   befores = { before_handler },
-- })
function _M.hook_function(group_name, parent, function_key, max_args, handlers)
  assert(type(group_name) == "string", "group_name must be a string")
  assert(type(parent) == "table", "parent must be a table")
  assert(type(function_key) == "string", "function_key must be a string")

  local is_varargs = max_args == "varargs"
  if not is_varargs then
    assert(type(max_args) == "number", 'max_args must be a number or "varargs"')
    assert(max_args >= 0 and max_args <= 8, 'max_args must be >= 0 and <= 8, or "varargs"')
  end

  local original_func = parent[function_key]
  assert(type(original_func) == "function", "parent[" .. function_key .. "] must be a function")

  if is_varargs then
    parent[function_key] = wrap_function_vararg(group_name, original_func, handlers)
  else
    parent[function_key] = wrap_function(max_args, group_name, original_func, handlers)
  end
end


--- Registers a new hook
-- The hook handler function is executed when `run_hook` is called with the
-- same `group_name` and `hook_name`.
--
-- @function dynamic_hook:hook
-- @tparam string group_name The name of the hook group
-- @tparam string hook_name The name of the hook
-- @tparam table handler The hook function
function _M.hook(group_name, hook_name, handler)
  assert(type(group_name) == "string", "group_name must be a string")
  assert(type(hook_name) == "string", "hook_name must be a string")
  assert(type(handler) == "function", "handler must be a function")

  local hooks = NON_FUNCTION_HOOKS[group_name]
  if not hooks then
    hooks = {}
    NON_FUNCTION_HOOKS[group_name] = hooks
  end

  hooks[hook_name] = handler
end


--- Checks if a hook group is enabled.
-- If a group is enabled, its hooks can be executed when `run_hook` is called
-- with the corresponding `group_name` and `hook_name` parameters.
--
-- @function dynamic_hook:is_group_enabled
-- @tparam string group_name The name of the hook group
-- @treturn boolean `true` if the group is enabled, `false` otherwise
function _M.is_group_enabled(group_name)
  assert(type(group_name) == "string", "group_name must be a string")

  if ALWAYS_ENABLED_GROUPS[group_name] then
    return true
  end

  if not get_request() then
    return false
  end

  local dynamic_hook = ngx.ctx.dynamic_hook
  if not dynamic_hook then
    return false
  end

  local enabled_groups = dynamic_hook.enabled_groups
  if not enabled_groups[group_name] then
    return false
  end

  return true
end


--- Runs a hook
-- Runs the hook registered for the given `group_name` and `hook_name` (if the
-- group is enabled).
--
-- @function dynamic_hook:run_hook
-- @tparam string group_name The name of the hook group
-- @tparam string hook_name The name of the hook
-- @tparam any `a1, a2, ..., a8` Arguments passed to the hook function
-- @tparam any ... Additional arguments passed to the hook function
-- @usage
-- -- Run the "my_hook" hook of the "my_group" group
-- dynamic_hook.run_hook("my_group", "my_hook", arg1, arg2)
function _M.run_hook(group_name, hook_name, a1, a2, a3, a4, a5, a6, a7, a8, ...)
  assert(type(group_name) == "string", "group_name must be a string")
  assert(type(hook_name) == "string", "hook_name must be a string")

  if not _M.is_group_enabled(group_name) then
    return
  end

  local hooks = NON_FUNCTION_HOOKS[group_name]
  if not hooks then
    return
  end

  local handler = hooks[hook_name]
  if not handler then
    return
  end

  local argc = select("#", ...)
  local ok, err
  if argc == 0 then
    ok, err = pcall(handler, a1, a2, a3, a4, a5, a6, a7, a8)
  else
    ok, err = pcall(handler, a1, a2, a3, a4, a5, a6, a7, a8, ...)
  end

  if not ok then
    ngx_log(ngx_WARN, "failed to run dynamic hook ", group_name, ".", hook_name, ": ", err)
  end
end


--- Enables a hook group for the current request
--
-- @function dynamic_hook:enable_on_this_request
-- @tparam string group_name The name of the hook group to enable
-- @tparam table (optional) ngx_ctx The Nginx context object
function _M.enable_on_this_request(group_name, ngx_ctx)
  assert(type(group_name) == "string", "group_name must be a string")

  ngx_ctx = ngx_ctx or ngx.ctx
  if ngx_ctx.dynamic_hook then
    ngx_ctx.dynamic_hook.enabled_groups[group_name] = true
  else
    ngx_ctx.dynamic_hook = {
      enabled_groups = {
        [group_name] = true
      },
    }
  end
end


--- Enables a hook group for all requests
--
-- @function dynamic_hook:enable_by_default
-- @tparam string group_name The name of the hook group to enable
function _M.enable_by_default(group_name)
  assert(type(group_name) == "string", "group_name must be a string")

  ALWAYS_ENABLED_GROUPS[group_name] = true
end


--- Disables a hook group that was enabled with `enable_by_default`
--
-- @function dynamic_hook:disable_by_default
-- @tparam string group_name The name of the hook group to disable
function _M.disable_by_default(group_name)
  assert(type(group_name) == "string", "group_name must be a string")

  ALWAYS_ENABLED_GROUPS[group_name] = nil
end


return _M
