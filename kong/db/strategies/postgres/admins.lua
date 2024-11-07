-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local concat = table.concat

local Admins = {}


function Admins:select_by_username_ignore_case(username)
  local qs = fmt(
    "SELECT * FROM admins WHERE LOWER(username) = LOWER(%s);",
    kong.db.connector:escape_literal(username))

  return kong.db.connector:query(qs, "read")
end

function Admins:update_workspaces(admin, default_role, workspace, credential)
  local connector = kong.db.connector
  local consumer = admin.consumer
  local rbac_user = admin.rbac_user
  local ws_id = workspace.id

  local sql = concat {
    "BEGIN;\n",
    fmt("UPDATE rbac_roles SET ws_id = %s WHERE id = %s and is_default = true;",
      connector:escape_literal(ws_id),
      connector:escape_literal(default_role.id)), "\n",
    fmt("UPDATE rbac_users SET ws_id = %s WHERE id = %s;",
      connector:escape_literal(ws_id),
      connector:escape_literal(rbac_user.id)), "\n",
    fmt("UPDATE consumers SET ws_id = %s WHERE id = %s;",
      connector:escape_literal(ws_id),
      connector:escape_literal(consumer.id)), "\n",
  }

  if credential then
    sql = concat {
      sql,
      fmt("UPDATE %s SET ws_id = %s WHERE id = %s;",
        credential.name,
        connector:escape_literal(ws_id),
        connector:escape_literal(credential.id)), "\n"
    }
  end

  sql = concat { sql, "COMMIT;\n" }
  local res, err = connector:query(sql)
  if err then
    connector:query("ROLLBACK;")
    return nil, err
  end

  return res
end

return Admins
