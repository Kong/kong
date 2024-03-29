-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local setmetatable = setmetatable


local options = {}


function options.new(oic, opts)
  return setmetatable({ oic = oic, defaults = opts }, options)
end


function options:__index(k)
  local def = self.defaults[k]
  if def ~= nil then
    return def
  end

  return options[k]
end


function options:reset(opts)
  self.defaults = opts
  return self
end


return options
