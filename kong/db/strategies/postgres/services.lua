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
