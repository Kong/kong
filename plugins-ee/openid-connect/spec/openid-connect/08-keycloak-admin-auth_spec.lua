-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson          = require "cjson.safe"
local helpers        = require "spec.helpers"
local ee_helpers     = require "spec-ee.helpers"
local sub            = string.sub
local find           = string.find
local utils          = require "kong.tools.utils"
local rbac           = require "kong.rbac"
local http           = require "resty.http".new()
local keycloak_api   = require "spec-ee.fixtures.keycloak_api"

local admin_client
local PLUGIN_NAME    = "openid-connect"
local PASSWORD       = "doe"
local cloak_settings = keycloak_api.cloak_settings()
local KONG_HOST      = "localhost"

local function get_access_token(client)
  local res = keycloak_api.auth(client)
  assert.response(res).has.status(200)
  local json = assert.response(res).has.jsonbody()
  assert.is_not_nil(json)
  assert.is_not_nil(json.access_token)

  return "bearer " .. json.access_token
end

local function do_cloak_request(handler, client, has_body, status, ...)
  local res = handler(client, get_access_token(client), ...)
  status = status or 200
  assert.response(res).has.status(status)
  if has_body then
    return assert.response(res).has.jsonbody()
  end
end

local function get_user_by_username(client, username)
  local json = do_cloak_request(keycloak_api.get_users, client, true, nil, username)
  local user = json and json[1]
  return user
end

local function get_group_by_name(client, name)
  local json = do_cloak_request(keycloak_api.get_groups, client, true, nil, name)
  for _, group in ipairs(json) do
    if group and group.name == name then
      return group
    end
  end
  return nil
end

local function default_login_handler(res, cookie)
  assert.equal(302, res.status)
  -- after sending login data to the login action page, expect a redirect
  local upstream_url = res.headers["Location"]
  local ures, err = http:request_uri(upstream_url, {
    headers = {
      -- authenticate using the cookie from the initial request
      Cookie = cookie,
    }
  })
  assert.is_nil(err)
  assert.equal(200, ures.status)

end

local function authentication(username, login_handler)
  local res = assert(admin_client:send {
    method = "POST",
    path = "/auth",
  })

  assert.response(res).has.status(302)
  local redirect = res.headers["Location"]
  -- get authorization=...; cookie
  local auth_cookie = res.headers["Set-Cookie"]
  local auth_cookie_cleaned = sub(auth_cookie, 0, find(auth_cookie, ";") - 1)
  local rres, err = http:request_uri(redirect, {
    headers = {
      -- impersonate as browser
      ["User-Agent"] =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", -- luacheck: ignore
      ["Host"] = cloak_settings.host,
    }
  })
  assert.is_nil(err)
  assert.equal(200, rres.status)

  local cookies = rres.headers["Set-Cookie"]
  local user_session
  local user_session_header_table = {}
  for _, cookie in ipairs(cookies) do
    user_session = sub(cookie, 0, find(cookie, ";") - 1)
    if find(user_session, 'AUTH_SESSION_ID=', 1, true) ~= 1 then
      -- auth_session_id is dropped by the browser for non-https connections
      table.insert(user_session_header_table, user_session)
    end
  end
  -- get the action_url from submit button and post username:password
  local action_start = find(rres.body, 'action="', 0, true)
  local action_end = find(rres.body, '"', action_start + 8, true)
  local login_button_url = string.sub(rres.body, action_start + 8, action_end - 1)
  -- the login_button_url is endcoded. decode it
  login_button_url = string.gsub(login_button_url, "&amp;", "&")
  -- build form_data
  local form_data = "username=" .. username .. "&password=" .. PASSWORD .. "&credentialId="
  local opts = {
    method = "POST",
    body = form_data,
    headers = {
      -- impersonate as browser
      ["User-Agent"] =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36",                  --luacheck: ignore
      ["Host"] = cloak_settings.host,
      -- due to form_data
      ["Content-Type"] = "application/x-www-form-urlencoded",
      Cookie = user_session_header_table,
    }
  }
  local loginres, rerr = http:request_uri(login_button_url, opts)
  assert.is_nil(rerr)
  login_handler = login_handler or default_login_handler
  login_handler(loginres, auth_cookie_cleaned)
end

local function get_admin_auth_conf(mixin)
  local conf = {
    issuer = cloak_settings.issuer,
    client_id = { cloak_settings.client_id },
    client_secret = { cloak_settings.client_secret },
    authenticated_groups_claim = { "groups" },
    admin_claim = "email",
  }

  for key, value in pairs(mixin or {}) do
    conf[key] = value
  end

  return cjson.encode(conf)
end

for _, strategy in helpers.each_strategy() do
  describe("Admin auth API authentication on #" .. strategy, function()
    describe("#openid-connect - authentication", function()
      local _, db
      local ROLE_NAME = "super-admin"
      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, {
          "admins",
          "plugins",
        }, { PLUGIN_NAME })
        local redirect_uri = string.format("http://%s:9001/auth", KONG_HOST)
        assert(helpers.start_kong({
          plugins                = "bundled," .. PLUGIN_NAME,
          database               = strategy,
          nginx_conf             = "spec/fixtures/custom_nginx.template",
          enforce_rbac           = "on",
          admin_gui_auth         = PLUGIN_NAME,
          admin_listen           = "0.0.0.0:9001",
          admin_gui_session_conf = [[
            {"secret":"Y29vbGJlYW5z","storage":"kong","cookie_secure":false}
          ]],
          admin_gui_auth_conf    = get_admin_auth_conf({
            redirect_uri = { redirect_uri },
          })
        }))

        local default_ws = db.workspaces:select_by_name("default")
        assert(kong.db.rbac_roles:insert({
          name = ROLE_NAME,
          comment = "super Administrator role"
        }, { workspace = default_ws.id }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("The new admin first login success and correct mapping role", function()
        local username = "john.doe@konghq.com"
        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admins = db.admins:select_by_username(username)
        assert(username, admins.username)
        local rbac_user_id = admins.rbac_user and admins.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local ws = db.workspaces:select_by_name("default")
        local role = assert(db.rbac_roles:select_by_name(ROLE_NAME, { workspace = ws.id }))
        local rbac_user_roles = assert(db.rbac_user_roles:select({
          user = { id = rbac_user_id },
          role = { id = role.id }
        }))
        assert.is_not_nil(rbac_user_roles)
      end)
    end)

    describe("#openid-connect - with response_mode = form_post", function()
      local redirect_uri = string.format("http://%s:9001/auth", KONG_HOST)

      lazy_setup(function()
        local config = {
          plugins                = "bundled," .. PLUGIN_NAME,
          database               = strategy,
          prefix                 = helpers.test_conf.prefix,
          enforce_rbac           = "on",
          admin_gui_auth         = PLUGIN_NAME,
          admin_listen           = "0.0.0.0:9001",
          admin_gui_listen       = "0.0.0.0:9008",
          admin_gui_url          = "http://localhost:9008",
          admin_gui_session_conf = [[
            {"secret":"Y29vbGJlYW5z","storage":"kong","cookie_secure":false}
          ]],
          admin_gui_auth_conf    = get_admin_auth_conf({
            response_mode = "form_post",
            auth_methods = { "authorization_code", "session" },
            redirect_uri = { redirect_uri },
          })
        }

        local _, stderr, stdout = assert(helpers.start_kong(config))
        assert.matches("Kong started", stdout)
        assert.matches(
          [[[warn] admin_gui_auth_conf.response_mode only accept "query" when admin_gui_auth is "openid-connect"]],
          stderr, nil, true)
        assert.matches(
          [[[warn] admin_gui_auth_conf.auth_methods only accept "authorization_code" when admin_gui_auth is "openid-connect"]],
          stderr, nil, true)
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("it should be login successfully", function()
        -- begin auth via openid-connect
        authentication("john.doe@konghq.com", function(res, auth_cookie_cleaned)
          assert.equal(302, res.status)

          -- after sending login data to the login action page, expect a redirect
          local upstream_url = res.headers["Location"]
          local ures, err = http:request_uri(upstream_url, {
            headers = {
              -- authenticate using the cookie from the initial request
              Cookie = auth_cookie_cleaned,
            }
          })
          assert.is_nil(err)
          assert.equal(200, ures.status)
        end)
      end)
    end)

    describe("#openid-connect - mapping role with group", function()
      local _, db, keycloak_client
      local user, group_ws1, group_ws2, default_super_admin_group
      local username = "sam.stark@konghq.com"
      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, {
          "admins",
          "plugins",
          "groups",
          "rbac_roles",
          "rbac_user_roles",
          "rbac_user_groups",
          "rbac_role_endpoints",
          "workspaces"
        }, { PLUGIN_NAME })

        local redirect_uri = string.format("http://%s:9001/auth", KONG_HOST)
        assert(helpers.start_kong({
          plugins                = "bundled," .. PLUGIN_NAME,
          database               = strategy,
          nginx_conf             = "spec/fixtures/custom_nginx.template",
          enforce_rbac           = "on",
          admin_gui_auth         = PLUGIN_NAME,
          admin_listen           = "0.0.0.0:9001",
          admin_gui_session_conf = [[
            {"secret":"Y29vbGJlYW5z","storage":"kong","cookie_secure":false}
          ]],
          admin_gui_auth_conf    = get_admin_auth_conf({
            redirect_uri = { redirect_uri },
          })
        }))

        ee_helpers.register_rbac_resources(db, "default")
        admin_client = helpers.admin_client()
        keycloak_client = helpers.http_client(cloak_settings.ip, cloak_settings.port)

        -- retrieve user from keycloak
        user = get_user_by_username(keycloak_client, "sam")
        default_super_admin_group = get_group_by_name(keycloak_client, "default:super-admin")
        -- add two workspaces
        for i = 1, 2, 1 do
          local ws_name = "ws" .. i
          local ws = db.workspaces:insert({ name = ws_name })
          local read_only = assert(kong.db.rbac_roles:insert({
            name = "workspace-read-only",
            comment = "the read only for the workspace"
          }, { workspace = ws.id }))

          assert(kong.db.rbac_role_endpoints:insert({
            role = read_only,
            actions = 0x1, -- read mode
            endpoint = "*",
            workspace = ws_name,
            negative = false
          }))

          local name = "readonly_group_" .. ws_name
          local group = assert(kong.db.groups:insert({ name = name }))
          assert(kong.db.group_rbac_roles:insert({ group = group, rbac_role = read_only, workspace = ws }))
          -- add a new group to Keycloak
          do_cloak_request(keycloak_api.add_group, keycloak_client, false, 201, { name = name })
          local cloak_group = get_group_by_name(keycloak_client, name)

          if ws_name == "ws1" then
            group_ws1 = cloak_group
          end
          if ws_name == "ws2" then
            group_ws2 = cloak_group
          end
        end
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        if admin_client then
          admin_client:close()
        end

        if keycloak_client then
          do_cloak_request(keycloak_api.delete_group, keycloak_client, false, 204, group_ws1.id)
          do_cloak_request(keycloak_api.delete_group, keycloak_client, false, 204, group_ws2.id)
          keycloak_client:close()
        end
      end)

      local function update_rbac_token(rbac_user_id)
        local user_token = utils.random_string()
        local token_ident = rbac.get_token_ident(user_token)

        assert(kong.db.rbac_users:update(
          { id = rbac_user_id },
          {
            user_token = user_token,
            user_token_ident = token_ident
          }
        ))

        return user_token
      end

      it("the admin doesn't have any permissions for all workspaces", function()
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local user_token = update_rbac_token(rbac_user_id)

        -- should access ws1/services
        -- shouldn't access /default/services
        for _, ws in ipairs({ "ws1", "ws2", "default" }) do
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(403)
        end
      end)

      it("the admin has all workspaces permissions when add the group `default:super-admin` of IDP", function()
        -- add default:super-admin to admin
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id,
          default_super_admin_group.id)
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local user_token = update_rbac_token(rbac_user_id)

        -- should access ws1/services
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(200)
        end
      end)

      it("the admin has readonly permissions of the workspace ws1 when add the group `readonly_group_ws1` of IDP", function()
        -- remove default:super-admin from the admin
        do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, default_super_admin_group.id)
        -- add readonly_group_ws1 to the admin
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id, group_ws1.id)
        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local ws = db.workspaces:select_by_name("ws1")
        local role = assert(db.rbac_roles:select_by_name("workspace-read-only", { workspace = ws.id }))
        local rbac_user_roles = db.rbac_user_roles:select({
          user = { id = rbac_user_id },
          role = { id = role.id }
        })
        assert.is_nil(rbac_user_roles)

        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          assert.is_not_nil(rbac_user_group)
        end

        local user_token = update_rbac_token(rbac_user_id)

        -- should access ws1/services
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(ws_name == "ws1" and 200 or 403)
        end
      end)

      it("the admin should has both readonly permissions of the workspaces(ws1, ws2)", function()
        -- add readonly_group_ws2 to the admin
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id, group_ws2.id)

        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        for _, ws_name in ipairs({ "ws1", "ws2" }) do
          local ws = db.workspaces:select_by_name(ws_name)

          local role = assert(db.rbac_roles:select_by_name("workspace-read-only", { workspace = ws.id }))
          local rbac_user_roles = db.rbac_user_roles:select({
            user = { id = rbac_user_id },
            role = { id = role.id }
          })
          assert.is_nil(rbac_user_roles)
        end

        local rbac_user_groups = {}
        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          assert.is_not_nil(rbac_user_group)
          table.insert(rbac_user_groups, rbac_user_group)
        end
        assert.equal(2, #rbac_user_groups)

        local user_token = update_rbac_token(rbac_user_id)
        -- shouldn't access /default/services
        for _, ws in ipairs({ "ws1", "ws2", "default" }) do
          -- should access ws1/services
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(ws == "default" and 403 or 200)
        end
      end)

      it("the admin has readonly permissions of the workspace ws2 when remove the group `readonly_group_ws1` of IDP", function()
        do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, group_ws1.id)
        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)

        local rbac_user_groups = {}
        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          assert.is_not_nil(rbac_user_group)
          table.insert(rbac_user_groups, rbac_user_group)
        end
        assert.equal(1, #rbac_user_groups)

        local user_token = update_rbac_token(rbac_user_id)

        local res
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          -- should access ws2/services
          res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(ws_name == "ws2" and 200 or 403)
        end
      end)

      it("the admin doesn't have any permissions when remove the group `readonly_group_ws2` of IDP", function()
        do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, group_ws2.id)

        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)

        local user_token = update_rbac_token(rbac_user_id)

        local rbac_user_groups = {}
        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          table.insert(rbac_user_groups, rbac_user_group)
        end
        assert.equal(0, #rbac_user_groups)
        for _, ws in ipairs({ "ws1", "ws2", "default" }) do
          -- should access ws1/services
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(403)
        end
      end)

      it("the admin doesn't have any permissions when delete group `readonly_group_ws2`", function()
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id, group_ws2.id)

        -- begin auth via openid-connect
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)

        local user_token = update_rbac_token(rbac_user_id)

        local rbac_user_groups = {}
        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          table.insert(rbac_user_groups, rbac_user_group)
        end
        assert.equal(1, #rbac_user_groups)
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          -- should access ws1/services
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(ws_name == "ws2" and 200 or 403)
        end

        -- delete the group `readonly_group_ws2`
        local group = assert(kong.db.groups:select_by_name("readonly_group_ws2"))
        assert(kong.db.groups:delete(group))

        -- begin auth via openid-connect
        authentication(username)

        rbac_user_groups = {}
        for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
          table.insert(rbac_user_groups, rbac_user_group)
        end
        assert.equal(0, #rbac_user_groups)
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          -- should access ws1/services
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(403)
        end

      end)

      it("the admin should doesn't have any permissions when remove the group `default:super-admin` again", function()
        -- add default:super-admin to admin
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id,
          default_super_admin_group.id)
        authentication(username)
        -- login success
        local admin = db.admins:select_by_username(username)
        assert(username, admin.username)
        local rbac_user_id = admin.rbac_user and admin.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local user_token = update_rbac_token(rbac_user_id)

        -- should access ws1/services
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(200)
        end

        -- remove default:super-admin from admin
        do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id,
          default_super_admin_group.id)
        authentication(username)
        -- login success

        -- should access ws1/services
        for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
          local res = assert(admin_client:send {
            method = "GET",
            path = "/" .. ws_name .. "/services",
            headers = {
              ["Kong-Admin-Token"] = user_token
            }
          })
          assert.response(res).has.status(403)
        end
      end)
    end)
  end)
end
