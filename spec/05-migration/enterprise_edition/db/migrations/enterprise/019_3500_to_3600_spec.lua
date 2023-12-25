-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"
local fmt = string.format

local WS_ROLES = {
  default = { roles = { "admin" } },
  non_default = { roles = { "workspace-admin", "workspace-portal-admin" } }
}

describe("database migration", function()
  uh.all_phases("has created the expected new columns", function()
    assert.table_has_column("audit_objects", "removed_from_entity", "text")
  end)
  uh.new_after_finish("the default role `admin` should has missing endpoints", function()
    local db = uh.get_database()
    local connector = db.connector
    local workspaces = assert(connector:query("SELECT * FROM workspaces;"))
    assert.not_nil(workspaces[1])

    for _, workspace in ipairs(workspaces) do
      local ws_role = WS_ROLES[workspace.name == "default" and "default" or "non_default"]
      local ws_name = workspace.name == "default" and "*" or workspace.name

      for _, role in pairs(ws_role.roles) do
        -- retrieve the role of the workspace
        local admin_role = assert(connector:query(fmt("SELECT * FROM rbac_roles WHERE name='%s' and ws_id='%s';",
          role, workspace.id)))
        local role_id = admin_role[1] and admin_role[1].id

        assert.not_nil(role_id)
        -- check the endpoints of the role.
        for _, endpoint in ipairs({ "/admins", "/admins/*" }) do
          local rbac_role_endpoint = assert(connector:query(fmt(
            "SELECT * FROM rbac_role_endpoints WHERE role_id='%s' and workspace='%s' and endpoint='%s'",
            role_id, ws_name, endpoint)))
          assert.not_nil(rbac_role_endpoint[1])
        end
      end
    end
  end)
end)
