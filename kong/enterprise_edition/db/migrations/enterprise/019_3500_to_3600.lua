-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format

local WS_ROLES = {
  default = { workspace = "*", roles = { "admin" } },
  non_default = { workspace = nil, roles = { "workspace-admin", "workspace-portal-admin" } }
}

local ADMINS_ENDPOINTS = { {
  endpoint = "/admins",
  actions = 15,
  negative = true,
}, {
  endpoint = "/admins/*",
  actions = 15,
  negative = true,
} }

local function is_not_exist_endpoint(connector, role_id, workspace, endpoint)
  local rbac_role_endpoint = assert(connector:query(fmt(
    "SELECT * FROM rbac_role_endpoints WHERE role_id='%s' and workspace='%s' and endpoint='%s'",
    role_id, workspace, endpoint)))
  return not rbac_role_endpoint[1]
end

local function add_rbac_role_endpoints(connector, workspace, role_id)
  for _, endpoint in ipairs(ADMINS_ENDPOINTS) do
    if is_not_exist_endpoint(connector, role_id, workspace, endpoint.endpoint) then
      assert(connector:query(fmt(
        "INSERT INTO rbac_role_endpoints(role_id, workspace, endpoint, actions, negative) VALUES ('%s', '%s', '%s', %d, %s);",
        role_id, workspace, endpoint.endpoint, endpoint.actions, tostring(endpoint.negative))))
    end
  end
end

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "audit_objects" ADD removed_from_entity TEXT;
      EXCEPTION WHEN duplicate_column THEN
        -- Do nothing, accept existing state
      END;
      $$;

      CREATE TABLE IF NOT EXISTS rbac_user_groups(
        user_id uuid NOT NULL REFERENCES rbac_users(id) ON DELETE CASCADE,
        group_id uuid NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        PRIMARY KEY(user_id, group_id)
      );
    ]],
    teardown = function(connector)
      -- retrieve all workspace
      local workspaces = assert(connector:query("SELECT * FROM workspaces;"))
      for _, workspace in ipairs(workspaces) do
        local ws_role = WS_ROLES[workspace.name == "default" and "default" or "non_default"]

        for _, role in pairs(ws_role.roles) do
          -- retrieve the role of the workspace
          local admin_role = assert(connector:query(fmt("SELECT * FROM rbac_roles WHERE name='%s' and ws_id='%s';",
            role, workspace.id)))
          -- insert the endpoints of the role.
          if admin_role[1] then
            add_rbac_role_endpoints(connector, ws_role.workspace or workspace.name, admin_role[1].id)
          end
        end
      end
    end,
  },
}
