-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local cjson      = require "cjson"
local bit        = require "bit"
local rbac       = require "kong.rbac"
local bor        = bit.bor
local ee_helpers = require "spec-ee.helpers"
local enums      = require "kong.enterprise_edition.dao.enums"
local fmt = string.format

local admin_client

local function admin_request(method, path, body, excpected_status, token)
  local res = assert(admin_client:send {
    method = method,
    path = path,
    headers = {
      ["Content-Type"] = "application/json",
      ["Kong-Admin-Token"] = token,
    },
    body = body
  })

  local response = assert.res_status(excpected_status or 200, res)
  if not res.has_body then
    return nil
  end
  return cjson.decode(response)
end

local function insert_admin(db, admin_body, role_name, token, workspace)
  ngx.ctx.workspace = workspace
  local admin = assert(db.admins:insert(admin_body))

  local rbac_user = assert(db.rbac_users:update({ id = admin.rbac_user.id }, {
    user_token = token,
    user_token_ident = cjson.null,
  }))

  local admin_role
  if role_name then
    admin_role = db.rbac_roles:select_by_name(role_name, { workspace = workspace })
    assert(db.rbac_user_roles:insert({
      user = rbac_user,
      role = admin_role,
    }))
  end

  return admin, admin_role
end

local function calculate_actions(actions)
  local bitfield_all_actions = 0x0
  for k in pairs(actions) do
    bitfield_all_actions = bor(bitfield_all_actions, rbac.actions_bitfields[actions[k]])
  end

  return bitfield_all_actions
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API - RBAC #" .. strategy, function()
    local db

    local workspaces = { "default", "ws1" }

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, nil, nil, nil, false)

      assert(helpers.start_kong({
        database     = strategy,
        admin_gui_auth = "basic-auth",
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
        nginx_conf   = "spec/fixtures/custom_nginx.template",
        enforce_rbac = "on",
      }))

      for _, ws_name in ipairs(workspaces) do
        if ws_name == "default" then
          ee_helpers.register_rbac_resources(db)
        else
          local ws = assert(db.workspaces:insert({
            name = ws_name,
          }))
          ee_helpers.register_rbac_resources(db, ws_name, ws)
        end
      end
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = assert(helpers.admin_client())
    end)

    after_each(function()
      if admin_client then admin_client:close() end
    end)

    for _, ws_name in pairs(workspaces) do
      describe("the super-admin with the role of admin when the workspace is " .. ws_name, function()
        local admin, admin_role
        local token = ws_name .. "_handyshake"
        local workspace

        lazy_setup(function()
          workspace = db.workspaces:select_by_name(ws_name)
          admin, admin_role = insert_admin(db, {
            username = workspace.name .. "-super-admin",
            custom_id = workspace.name .. "-super-admin",
            email = workspace.name .. "_super-admin@test.com",
            status = enums.CONSUMERS.STATUS.APPROVED,
          }, "super-admin", token, workspace.id)
        end)

        it("the admin should not add role by themselves", function()
          local json = admin_request("POST",
            fmt("/%s/admins/%s/roles", workspace.name, admin.id),
            {
              roles = "admin"
            },
            403,
            token
          )
          assert.same("the admin should not update their own roles", json.message)

          json = admin_request("DELETE",
            fmt("/%s/admins/%s/roles", workspace.name, admin.id),
            {
              roles = "super-admin"
            },
            403,
            token
          )
          assert.same("the admin should not update their own roles", json.message)
        end)

        it("the admin should not add an endpoint to its role", function()
          -- post request with role id
          json = admin_request("POST",
            fmt("/%s/rbac/roles/%s/endpoints", workspace.name, admin_role.id),
            {
              endpoint = "/test",
              actions = "read"
            },
            403,
            token
          )
          assert.same("the admin should not update their own roles", json.message)

          -- post request with role name
          json = admin_request("POST",
            fmt("/%s/rbac/roles/%s/endpoints", workspace.name, admin_role.name),
            {
              endpoint = "/test",
              actions = "read"
            },
            403,
            token
          )
          assert.same("the admin should not update their own roles", json.message)
        end)

        it("admin can add endpoints for other roles except their own roles", function()
          local admin_role = db.rbac_roles:select_by_name("admin", { workspace = workspace.id })
          json = admin_request("POST",
            fmt("/%s/rbac/roles/%s/endpoints", workspace.name, admin_role.id),
            {
              endpoint = "/test",
              actions = "read"
            },
            201,
            token
          )
          assert.same("/test", json.endpoint)
        end)

        it("the admin should not delete their own roles", function()
          -- delete request with role id
          json = admin_request("DELETE",
            fmt("/%s/rbac/roles/%s", workspace.name, admin_role.id),
            nil,
            403,
            token
          )
          assert.same("the admin should not delete their own roles", json.message)
          -- delete request with role name
          json = admin_request("DELETE",
            fmt("/%s/rbac/roles/%s", workspace.name, admin_role.name),
            nil,
            403,
            token
          )
          assert.same("the admin should not delete their own roles", json.message)
        end)

        it("the admin should not update or delete endpoint to its own roles", function()
          -- patch request with role id
          json = admin_request("PATCH",
            fmt("/%s/rbac/roles/%s/endpoints/%s/*", workspace.name, admin_role.id, workspace.name),
            nil,
            403,
            token
          )
          assert.same("the admin should not update or delete their own endpoints", json.message)

          -- delete request with role id
          json = admin_request("DELETE",
            fmt("/%s/rbac/roles/%s/endpoints/%s/*", workspace.name, admin_role.id, workspace.name),
            nil,
            403,
            token
          )
          assert.same("the admin should not update or delete their own endpoints", json.message)

          -- patch request with role name
          json = admin_request("PATCH",
            fmt("/%s/rbac/roles/%s/endpoints/%s/*", workspace.name, admin_role.name, workspace.name),
            nil,
            403,
            token
          )
          assert.same("the admin should not update or delete their own endpoints", json.message)

          -- delete request with role name
          json = admin_request("DELETE",
            fmt("/%s/rbac/roles/%s/endpoints/%s/*", workspace.name, admin_role.name, workspace.name),
            nil,
            403,
            token
          )
          assert.same("the admin should not update or delete their own endpoints", json.message)
        end)

        it("the admin can update or delete endpoint for other roles", function()
          local admin_role = db.rbac_roles:select_by_name("admin", { workspace = workspace.id })

          -- retrieve the endpoint `/test` of the role `admin`
          json = admin_request("GET",
            fmt("/%s/rbac/roles/%s/endpoints/%s/test", workspace.name, admin_role.id, workspace.name),
            nil, 200, token)

          assert.same(calculate_actions({ "read" }), calculate_actions(json.actions))
          assert.same(false, json.negative)

          --update the endpoint actions is `update,delete`
          json = admin_request("PATCH",
            fmt("/%s/rbac/roles/%s/endpoints/%s/test", workspace.name, admin_role.id, workspace.name),
            {
              negative = true,
              actions = "update,delete"
            },
            200,
            token
          )

          assert.same(calculate_actions({ "update", "delete" }), calculate_actions(json.actions))
          assert.same(true, json.negative)

          admin_request("DELETE",
            fmt("/%s/rbac/roles/%s/endpoints/%s/test", workspace.name, admin_role.id, workspace.name),
            nil,
            204,
            token
          )

          admin_request("GET",
            fmt("/%s/rbac/roles/%s/endpoints/%s/test", workspace.name, admin_role.id, workspace.name),
            nil, 404, token)
        end)

        it("the non-super-admin should add role by super-admin", function()
          local another_admin = insert_admin(db, {
            username = workspace.name .. "_another_admin",
            custom_id = workspace.name .. "_another_admin",
            email = workspace.name .. "_another_admin@test.com",
            status = enums.CONSUMERS.STATUS.APPROVED
          }, nil, workspace.name .. "_another_admin_token", workspace.id)

          local roles = admin_request("POST",
            fmt("/%s/admins/%s/roles", workspace.name, another_admin.id),
            {
              roles = "admin"
            },
            201,
            token
          )
          assert.equals(1, #roles.roles)

          admin_request("DELETE",
            fmt("/%s/admins/%s/roles", workspace.name, another_admin.id),
            {
              roles = "admin"
            },
            204,
            token
          )

          roles = admin_request("GET",
            fmt("/%s/admins/%s/roles", workspace.name, another_admin.id),
            nil,
            200,
            token
          )
          assert.equals(0, #roles.roles)
        end)
      end)
    end
  end)
end
