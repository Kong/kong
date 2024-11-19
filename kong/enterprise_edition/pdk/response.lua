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
local insert = table.insert

local check_phase = phase_checker.check
local PHASES = phase_checker.phases


local function gen_func_register_hook(hooks)
  return function(method, hook_method, ctx)
    check_phase(PHASES.init_worker)
      local hook = { method = hook_method, ctx = ctx }
      if hooks[method] then
        insert(hooks[method], hook)
      else
        hooks[method] = { hook }
      end
  end
end


local function gen_mt_func__index_hook(hooks, response, k)
  return function(...)
    local func = response[k]
    local method_hooks = hooks[k]
    local count = method_hooks and #hooks[k] or 0
    if count == 0 then
      return func(...)

    elseif count == 1 then
        local method = method_hooks[1].method
        local ctx = method_hooks[1].ctx
        if ctx then
          return func(method(ctx, ...))
        else
          return func(method(...))
        end

    elseif count == 2 then
      local m1 = method_hooks[1].method
      local c1 = method_hooks[1].ctx
      local m2 = method_hooks[2].method
      local c2 = method_hooks[2].ctx
      if c1 and c2 then
        return func(m2(c2, m1(c1, ...)))
      elseif c1 then
        return func(m2(m1(c1, ...)))
      elseif c2 then
        return func(m2(c2, m1(...)))
      else
        return func(m2(m1(...)))
      end

    else
      local arg = pack(...)
      for i = 1, count do
        local hook = method_hooks[i]
        if hook.ctx then
          arg = pack(hook.method(hook.ctx, unpack(arg)))
        else
          arg = pack(hook.method(unpack(arg)))
        end
      end
      return func(unpack(arg))
    end
  end
end


local function gen_mt_func___index(hooks, response)
  return function(_, k)
    if hooks[k] then
      return gen_mt_func__index_hook(hooks, response, k)
    else
      return response[k]
    end
  end
end


local function gen_mt_func___newindex(response)
  return function(_, k, v)
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
