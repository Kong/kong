-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    { config = {
        type = "record",
        fields = {
          { per_consumer = { type = "boolean", default = false }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
