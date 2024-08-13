local _M = {}
local timing

local function before_toip(qname, _port, _dnsCacheOnly, _try_list)
  timing.enter_context("dns")
  timing.enter_context(qname)
  timing.enter_context("resolve")
end


local function after_toip()
  timing.leave_context() -- leave resolve
  timing.leave_context() -- leave qname
  timing.leave_context() -- leave dns
end


function _M.register_hooks(timing_module)
  local req_dyn_hook = require("kong.dynamic_hook")

  --[[
    The `toip()` function can receive <= 4 arguments (including `self`).
    Here is the signature of the `toip()` function:
    function toip(self, qname, port, dnsCacheOnly, try_list)
  --]]
  local client = assert(package.loaded["kong.resty.dns.client"])
  req_dyn_hook.hook_function("timing", client, "toip", 4, {
    befores = { before_toip },
    afters = { after_toip },
  })

  timing = timing_module
end


return _M
