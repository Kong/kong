-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local fmt  = string.format

local Services = {}

function Services:select_by_ca_certificate(ca_id, limit)
  local limit_condition = ""
  if limit then
    limit_condition = "LIMIT " .. kong.db.connector:escape_literal(limit)
  end

  local qs = fmt(
    "SELECT * FROM services WHERE %s = ANY(ca_certificates) %s;",
    kong.db.connector:escape_literal(ca_id),
    limit_condition)

  return kong.db.connector:query(qs)
end

return Services
