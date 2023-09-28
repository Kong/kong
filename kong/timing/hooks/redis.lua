-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local _M = {}

local timing


local function before()
  timing.enter_context("redis")
end


local function after()
  timing.leave_context() -- leave redis
end


function _M.register_hooks(timing_module)
  local req_dyn_hook = require("kong.dynamic_hook")

  local redis = require("resty.redis")
  for method_name, _ in pairs(redis) do
    if type(redis[method_name]) ~= "function" then
      goto continue
    end

    req_dyn_hook.hook_function("timing", redis, method_name, "varargs", {
      befores = { before },
      afters = { after },
    })

    ::continue::
  end

  timing = timing_module
end



return _M
