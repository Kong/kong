-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


-- Parameter Serialization: https://swagger.io/docs/specification/serialization/

local _M = {}

local DEFAULT = {
  ["path"] = { style = "simple", explode = false },
  ["query"] = { style = "form", explode = true },
  ["header"] = { style = "simple", explode = false },
  ["cookie"] = { style = "form", explode = true },
}

function _M.serialization_args(parameter)
  local default = DEFAULT[parameter["in"]]

  if default == nil then
    error("not allow: " .. parameter["in"])
  end

  local style = default.style
  if parameter.style ~= nil then
    style = parameter.style
  end

  local explode = default.explode
  if parameter.explode ~= nil then
    explode = parameter.explode
  end

  return style, explode
end

return _M
