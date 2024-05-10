-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local phase_checker = require "kong.pdk.private.phases"
local kong_table = require "kong.tools.table"

local pack = kong_table.pack
local unpack = kong_table.unpack

local check_phase = phase_checker.check
local PHASES = phase_checker.phases


local function gen_func_register_hook(hooks)
  return function(method, hook_method, ctx)
    check_phase(PHASES.init_worker)
      local hook = { method = hook_method, ctx = ctx }
      if hooks[method] then
        table.insert(hooks[method], hook)
      else
        hooks[method] = { hook }
      end
  end
end


local function gen_mt_func__index_hook(hooks, response, k)
  return function(...)
    local arg = pack(...)
    for _, hook in ipairs(hooks[k]) do
      if hook.ctx then
        arg = pack(hook.method(hook.ctx, unpack(arg)))
      else
        arg = pack(hook.method(unpack(arg)))
      end
    end
    return response[k](unpack(arg))
  end
end


local function gen_mt_func___index(hooks, response)
  return function(_self, k)
    if hooks[k] then
      return gen_mt_func__index_hook(hooks, response, k)
    else
      return response[k]
    end
  end
end


local function gen_mt_func___newindex(response)
  return function(_self, k, v)
    response[k] = v
  end
end


local function new(self, module, major_version)
  local _response = module.new(self, major_version)

  local hooks = {}
  local response = {
    register_hook = gen_func_register_hook(hooks),
  }

  local mt = {
    __index = gen_mt_func___index(hooks, _response),
    __newindex = gen_mt_func___newindex(_response),
  }

  setmetatable(response, mt)
  return response
end

return {
  new = new,
}
