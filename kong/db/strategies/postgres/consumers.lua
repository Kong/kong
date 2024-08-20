-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces = require "kong.workspaces"

local fmt = string.format
local get_workspace_id = workspaces.get_workspace_id

local Consumers = {}


function Consumers:select_by_username_ignore_case(username)
  local ws_id = get_workspace_id()
  local qs = fmt(
    "SELECT * FROM consumers WHERE username_lower = %s AND ws_id = %s;",
    kong.db.connector:escape_literal(username:lower()),
    kong.db.connector:escape_literal(ws_id))

  return kong.db.connector:query(qs, "read")
end

return Consumers
