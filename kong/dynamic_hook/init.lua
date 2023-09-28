-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local warp_function_gen = require("kong.dynamic_hook.wrap_function_gen")

local ngx               = ngx

local _M                = {
  TYPE = {
    BEFORE = 1,
    AFTER  = 2,
    BEFORE_MUT = 3,
    AFTER_MUT  = 4,
  },
}

local pcall             = pcall

local non_function_hooks = {
--[[
  [group_name] = {
    [hook_name] = <function>,
    ...
  },
  ...
--]]
}

local always_enabled_groups = {}

local wrap_functions = {
  [0] = warp_function_gen.generate_wrap_function(0),
  [1] = warp_function_gen.generate_wrap_function(1),
  [2] = warp_function_gen.generate_wrap_function(2),
  [3] = warp_function_gen.generate_wrap_function(3),
  [4] = warp_function_gen.generate_wrap_function(4),
  [5] = warp_function_gen.generate_wrap_function(5),
  [6] = warp_function_gen.generate_wrap_function(6),
  [7] = warp_function_gen.generate_wrap_function(7),
  [8] = warp_function_gen.generate_wrap_function(8),
  ["varargs"] = warp_function_gen.generate_wrap_function("varargs"),
}


function _M.hook_function(group_name, parent, child_key, max_args, handlers)
  assert(type(parent) == "table", "parent must be a table")
  assert(type(child_key) == "string", "child_key must be a string")

  if type(max_args) == "string" then
    assert(max_args == "varargs", "max_args must be a number or \"varargs\"")
    assert(handlers.before_mut == nil, "before_mut is not supported for varargs functions")

  else
    assert(type(max_args) == "number", "max_args must be a number or \"varargs\"")
    assert(max_args >= 0 and max_args <= 8, "max_args must be >= 0")
  end

  local old_func = parent[child_key]
  assert(type(old_func) == "function", "parent[" .. child_key .. "] must be a function")

  parent[child_key] = wrap_functions[max_args](always_enabled_groups, group_name, old_func, handlers)
end


function _M.hook(group_name, hook_name, handler)
  assert(type(group_name) == "string", "group_name must be a string")
  assert(type(hook_name) == "string", "hook_name must be a string")
  assert(type(handler) == "function", "handler must be a function")

  local hooks = non_function_hooks[group_name]
  if not hooks then
    hooks = {}
    non_function_hooks[group_name] = hooks
  end

  hooks[hook_name] = handler
end


function _M.run_hooks(group_name, hook_name, ...)
  if not always_enabled_groups[group_name] then
    local dynamic_hook = ngx.ctx.dynamic_hook
    if not dynamic_hook then
      return
    end

    local enabled_groups = dynamic_hook.enabled_groups
    if not enabled_groups[group_name] then
      return
    end
  end

  local hooks = non_function_hooks[group_name]
  if not hooks then
    return
  end

  local handler = hooks[hook_name]
  if not handler then
    return
  end

  local ok, err = pcall(handler, ...)
  if not ok then
    ngx.log(ngx.WARN,
            string.format("failed to run dynamic hook %s.%s: %s",
                          group_name, hook_name, err))
  end
end


function _M.enable_on_this_request(group_name)
  local info = ngx.ctx.dynamic_hook
  if not info then
    info = {
      enabled_groups = {},
    }
    ngx.ctx.dynamic_hook = info
  end

  info.enabled_groups[group_name] = true
end


function _M.always_enable(group_name)
  always_enabled_groups[group_name] = true
end


return _M
