-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local etrace
local etrace_enter_span
local etrace_add_string_attribute
local etrace_add_bool_attribute
local etrace_add_int64_attribute
local etrace_add_double_attribute
local etrace_exit_span


local function before()
  etrace_enter_span("redis")
end


local function after()
  etrace_exit_span() -- redis
end


function _M.globalpatches(etrace_module)
  local req_dyn_hook = require("kong.dynamic_hook")

  local redis = require("resty.redis")
  for method_name, _ in pairs(redis) do
    if type(redis[method_name]) ~= "function" then
      goto continue
    end

    req_dyn_hook.hook_function("etrace", redis, method_name, "varargs", {
      befores = { before },
      afters = { after },
    })

    ::continue::
  end

  etrace = etrace_module
  etrace_enter_span = etrace.enter_span
  etrace_add_string_attribute = etrace.add_string_attribute
  etrace_add_bool_attribute = etrace.add_bool_attribute
  etrace_add_int64_attribute = etrace.add_int64_attribute
  etrace_add_double_attribute = etrace.add_double_attribute
  etrace_exit_span = etrace.exit_span
end



return _M
