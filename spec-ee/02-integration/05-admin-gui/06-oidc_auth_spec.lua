-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local auth_plugin_helpers = require "kong.enterprise_edition.auth_plugin_helpers"


local username = "super-admin@test.com"
local admin

for _, strategy in helpers.each_strategy() do

  local function insert_ws_and_related_roles(ws_name)
    local ws = kong.db.workspaces:insert({ name = ws_name })

    assert(kong.db.rbac_roles:insert({
      name = "workspace-super-admin",
      comment = "super Administrator role"
    }, { workspace = ws.id }))

    assert(kong.db.rbac_roles:insert({
      name = "workspace-admin",
      comment = "Administrator role except RBAC"
    }, { workspace = ws.id }))

    return ws
  end

  local function insert_admin(ws_name, username)
    local default_ws = kong.db.workspaces:select_by_name(ws_name)
    ngx.ctx.workspace = default_ws.id

    return assert(kong.db.admins:insert({
      username = username
    }))
  end

  local function correct_setting_related_role_for_admin(claim_values, ws_roles)
    -- local admin = assert(kong.db.admins:select_by_username(username))
    auth_plugin_helpers.map_admin_roles_by_idp_claim(admin, claim_values)
    for ws_name, roles in pairs(ws_roles) do
      local ws = assert(kong.db.workspaces:select_by_name(ws_name))
      for _, role_name in ipairs(roles) do
        local role = assert(kong.db.rbac_roles:select_by_name(role_name, { workspace = ws.id }))
        local rbac_user_roles = assert(kong.db.rbac_user_roles:select({
          user = { id = admin.rbac_user.id },
          role = { id = role.id }
        }))
        assert.is_not_nil(rbac_user_roles)
      end
    end
  end

  describe("oidc auth with groups claim [#" .. strategy .. "]", function()

    lazy_setup(function()
      helpers.get_db_utils(nil, {})
      helpers.kong_exec("migrations reset --yes")
      helpers.kong_exec("migrations bootstrap", { password = "kong" })

      assert(helpers.start_kong({ database = strategy }))

      insert_ws_and_related_roles("ws01")
      insert_ws_and_related_roles("ws02")

      admin = insert_admin("default", username)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("oidc auth map_admin_roles_by_idp_claim", function()

      it("admin should have related roles of workspace[default,ws01]", function()
        correct_setting_related_role_for_admin(
          {
            "Everyone",
            "default:super-admin",
            "ws01:workspace-super-admin",
            "ws01:workspace-admin"
          },
          {
            ws01 = { "workspace-super-admin", "workspace-admin" },
            default = { "super-admin" }
          }
        )
      end)

      it("admin should have related roles of workspace[default,ws01,ws02]", function()
        correct_setting_related_role_for_admin(
          {
            "Everyone",
            "default:super-admin",
            "ws01:workspace-super-admin",
            "ws01:workspace-admin",
            "ws02:workspace-admin"
          },
          {
            default = { "super-admin" },
            ws01 = { "workspace-super-admin", "workspace-admin" },
            ws02 = { "workspace-admin" }
          }
        )
      end)

      it("admin related roles of workspace[default,ws01] and haven't role 'workspace-admin' of ws02", function()
        correct_setting_related_role_for_admin(
          {
            "Everyone",
            "default:super-admin",
            "ws01:workspace-super-admin",
            "ws01:workspace-admin"
          },
          {
            default = { "super-admin" },
            ws01 = { "workspace-super-admin", "workspace-admin" },
          }
        )

        local ws = kong.db.workspaces:select_by_name("ws02")
        local role = assert(kong.db.rbac_roles:select_by_name("workspace-admin", { workspace = ws.id }))
        local rbac_user_roles = kong.db.rbac_user_roles:select({
          user = { id = admin.rbac_user.id },
          role = { id = role.id }
        })
        assert.is_nil(rbac_user_roles)

      end)
    end)
  end)
end
