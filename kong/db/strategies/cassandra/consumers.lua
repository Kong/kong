-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces   = require "kong.workspaces"
local cassandra    = require "cassandra"

local fmt = string.format

local Consumers = {}


function Consumers:select_by_username_ignore_case(username)
  local ws_id = workspaces.get_workspace_id()
  local escaped_value = cassandra.text(fmt("%s:%s", ws_id, username:lower())).val
  local qs = fmt(
    "SELECT * FROM consumers WHERE username_lower = '%s';",
    escaped_value)

  local consumers, err = kong.db.connector:query(qs)

  for i,v in pairs(consumers) do
    if type(i) == "number" then
      consumers[i] = self:deserialize_row(consumers[i])
    end
  end

  return consumers, err
end

return Consumers
