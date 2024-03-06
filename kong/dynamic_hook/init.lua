local ngx = ngx
local type = type
local pcall = pcall
local select = select
local ipairs = ipairs
local assert = assert
local ngx_log = ngx.log
local ngx_WARN = ngx.WARN
local ngx_get_phase = ngx.get_phase


local _M = {
  TYPE = {
    BEFORE = 1,
    AFTER = 2,
    BEFORE_MUT = 3,
    AFTER_MUT = 4,
  },
}


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
  execute_hook_vararg(handlers.after_mut, "after_mut", group_name, ...)
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
    if should_execute_original_func(group_name) then
      a1, a2, a3, a4, a5, a6, a7, a8 = execute_original_func(max_args, original_func, a1, a2, a3, a4, a5, a6, a7, a8)
      
    else
      execute_hook(handlers.before_mut, "before_mut", group_name, a1, a2, a3, a4, a5, a6, a7, a8)
      execute_hooks(handlers.befores, "before", group_name, a1, a2, a3, a4, a5, a6, a7, a8)
      a1, a2, a3, a4, a5, a6, a7, a8 = execute_original_func(max_args, original_func, a1, a2, a3, a4, a5, a6, a7, a8)
      execute_hook(handlers.after_mut, "after_mut", group_name, a1, a2, a3, a4, a5, a6, a7, a8)
      execute_hooks(handlers.afters, "after", group_name, a1, a2, a3, a4, a5, a6, a7, a8)
    end
    return a1, a2, a3, a4, a5, a6, a7, a8
  end
end


function _M.hook_function(group_name, parent, child_key, max_args, handlers)
  assert(type(parent) == "table", "parent must be a table")
  assert(type(child_key) == "string", "child_key must be a string")

  local is_varargs = max_args == "varargs"
  if is_varargs then
    assert(handlers.before_mut == nil, "before_mut is not supported for varargs functions")
  else
    assert(type(max_args) == "number", 'max_args must be a number or "varargs"')
    assert(max_args >= 0 and max_args <= 8, 'max_args must be >= 0 and <= 8, or "varargs"')
  end

  local original_func = parent[child_key]
  assert(type(original_func) == "function", "parent[" .. child_key .. "] must be a function")

  if is_varargs then
    parent[child_key] = wrap_function_vararg(group_name, original_func, handlers)
  else
    parent[child_key] = wrap_function(max_args, group_name, original_func, handlers)
  end
end


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


function _M.is_group_enabled(group_name)
  if ALWAYS_ENABLED_GROUPS[group_name] then
    return true
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


function _M.run_hooks(group_name, hook_name, a1, a2, a3, a4, a5, a6, a7, a8, ...)
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


function _M.enable_on_this_request(group_name, ngx_ctx)
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


function _M.always_enable(group_name)
  ALWAYS_ENABLED_GROUPS[group_name] = true
end


return _M
