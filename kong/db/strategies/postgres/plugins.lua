-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong
local fmt  = string.format
local tb_insert = table.insert
local tb_concat = table.concat

local Plugins = {}

function Plugins:select_by_ca_certificate(ca_id, limit, plugin_names)
  local connector = kong.db.connector
  local escape_literal = connector.escape_literal
  local limit_condition = ""
  if limit then
    limit_condition = "LIMIT " .. escape_literal(connector, limit)
  end

  local name_condition = ""
  local escaped_names = {}
  if type(plugin_names) == "string" then
    tb_insert(escaped_names, "name = " .. escape_literal(connector, plugin_names))
  elseif type(plugin_names) == "table" then
    for name, _ in pairs(plugin_names) do
      tb_insert(escaped_names, "name = " .. escape_literal(connector, name))
    end
  end

  if #escaped_names > 0 then
    name_condition = "AND (" .. tb_concat(escaped_names, " OR ") .. ")"
  end

  local qs = fmt(
    "SELECT * FROM plugins WHERE config->'ca_certificates' ? %s %s %s;",
    escape_literal(connector, ca_id),
    name_condition,
    limit_condition)

  return connector:query(qs)
end

return Plugins
