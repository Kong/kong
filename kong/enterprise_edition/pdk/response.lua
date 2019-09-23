local phase_checker = require "kong.pdk.private.phases"

local check_phase = phase_checker.check
local PHASES = phase_checker.phases

local function new(self, module, major_version)
  local _response = module.new(self, major_version)

  local hooks = {}
  local response = {
    register_hook = function(method, _hook, ctx)
      check_phase(PHASES.init_worker)
      local hook = { method = _hook, ctx = ctx }
      if hooks[method] then
        table.insert(hooks[method], hook)
      else
        hooks[method] = { hook }
      end
    end,
  }

  local mt = {
    __index = function(self, k)
      if hooks[k] then
        return function(...)
          local arg = { ... }
          for _, hook in ipairs(hooks[k]) do
            if hook.ctx then
              arg = { hook.method(hook.ctx, unpack(arg)) }
            else
              arg = { hook.method(unpack(arg)) }
            end
          end
          return _response[k](unpack(arg))
        end
      else
        return _response[k]
      end
    end,
    __newindex = function(self, k, v)
      _response[k] = v
    end,
  }

  setmetatable(response, mt)
  return response
end

return {
  new = new,
}
