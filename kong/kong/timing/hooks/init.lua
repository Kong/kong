local _M = {}

-- order matters
local HOOKS = {
  "socket",
  "dns",
  "http",
  "redis",
}


function _M.register_hooks(timing_module)
  for _, hook_name in ipairs(HOOKS) do
    local hook_module = require("kong.timing.hooks." .. hook_name)
    hook_module.register_hooks(timing_module)
  end
end


return _M
