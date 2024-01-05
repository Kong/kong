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
