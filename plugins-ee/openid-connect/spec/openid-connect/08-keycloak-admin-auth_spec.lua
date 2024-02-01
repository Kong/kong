-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson          = require "cjson.safe"
local helpers        = require "spec.helpers"
local ee_helpers     = require "spec-ee.helpers"
local utils          = require "kong.tools.utils"
local rbac           = require "kong.rbac"
local http           = require "resty.http".new()
local keycloak_api   = require "spec-ee.fixtures.keycloak_api"

local sub            = string.sub
local gsub           = string.gsub
local find           = string.find

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

local ADMIN_API_PORT = 9001
local ADMIN_GUI_PORT = 9008
local ADMIN_API_LISTEN = "0.0.0.0:" .. ADMIN_API_PORT
local ADMIN_GUI_LISTEN = "0.0.0.0:" .. ADMIN_GUI_PORT

local ADMIN_API_BASE = "http://" .. KONG_HOST .. ":" .. ADMIN_API_PORT
local ADMIN_GUI_BASE = "http://" .. KONG_HOST .. ":" .. ADMIN_GUI_PORT

local REDIRECT_URL = ADMIN_API_BASE .. "/auth"
local LOGIN_REDIRECT_URL = ADMIN_GUI_BASE .. "/kconfig.js"
local LOGOUT_REDIRECT_URL = ADMIN_GUI_BASE .. "/kconfig.js?logout"

local startswith = function(s, start)
  return s and start and start ~= "" and s:sub(1, #start) == start
end

local function get_cookie_table(res)
  local t = res.headers["Set-Cookie"]
  if not t then
    return nil
  end

  return type(t) == "table" and t or { t }
end

local function init_auth(admin_client, username, password)
  -- Initiate the authentication flow via the /auth route
  local res, err = assert(admin_client:send {
    method = "POST",
    path = "/auth"
  })
  assert.is_nil(err)
  assert.response(res).has.status(302)

  local idp_auth_url = res.headers["Location"]

  local authorization_cookie
  -- Save the authorization cookie (set by the openid-connect plugin)
  for _, cookie in ipairs(assert(get_cookie_table(res))) do
    cookie = sub(cookie, 0, find(cookie, ";") - 1)
    if startswith(cookie, "authorization=") then
      authorization_cookie = cookie
      break
    end
  end

  -- Redirect to IdP (login form page)
  res, err = http:request_uri(idp_auth_url, {
    headers = {
      ["User-Agent"] =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", -- luacheck: ignore
      ["Host"] = cloak_settings.host,
    }
  })
  assert.is_nil(err)
  assert.equal(200, res.status)

  -- Get action url from <form />
  local action_t = [[action="]]
  local action_start = find(res.body, action_t, 1, true)
  local action_end = find(res.body, '"', action_start + #action_t, true)
  local idp_auth_action_url = sub(res.body, action_start + #action_t, action_end - 1)
  -- (Simply) decode the URL-encoded action URL
  idp_auth_action_url = gsub(idp_auth_action_url, "&amp;", "&")

  local idp_cookie = {}
  for _, cookie in ipairs(assert(get_cookie_table(res))) do
    cookie = sub(cookie, 0, find(cookie, ";") - 1)
    -- Drop AUTH_SESSION_ID because we are using plain HTTP endpoints
    if not startswith(cookie, "AUTH_SESSION_ID=") then
      table.insert(idp_cookie, cookie)
    end
  end

  -- Perform the form POST action
  res, err = http:request_uri(idp_auth_action_url, {
    method = "POST",
    body = "username=" .. username .. "&password=" .. password .. "&credentialId=",
    headers = {
      ["User-Agent"] =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36",                  --luacheck: ignore
      ["Host"] = cloak_settings.host,
      -- due to form_data
      ["Content-Type"] = "application/x-www-form-urlencoded",
      Cookie = idp_cookie,
    }
  })
  assert.is_nil(err)

  return res, authorization_cookie
end

-- Complete the authorization_code flow and get the session cookie
local function finalize_auth(url, auth_cookie, post_body)
  -- We will use the admin client
  assert(startswith(url, REDIRECT_URL))

  local opts = {
    method = "GET",
    headers = {
      ["Cookie"] = auth_cookie,
    },
  }

  if post_body then
    opts.method = "POST"
    opts.body = post_body
    opts.headers["Content-Type"] = "application/x-www-form-urlencoded"
  end

  -- Finalize the authorization_code flow
  local res, err = http:request_uri(url, opts)
  -- Should be a 302 response to LOGIN_REDIRECT_URL
  assert.is_nil(err)
  assert.equal(302, res.status)
  local redirect_url = res.headers["Location"]
  assert.equal(LOGIN_REDIRECT_URL, redirect_url)

  local session_cookie
  -- Save the session cookie (set by the openid-connect plugin)
  for _, cookie in ipairs(assert(get_cookie_table(res))) do
    cookie = sub(cookie, 0, find(cookie, ";") - 1)
    if startswith(cookie, "session=") then
      session_cookie = cookie
      break
    end
  end
  assert.is_not_nil(session_cookie)

  -- The admin is not created yet by this point because we have not sent requests with the
  -- session cookie

  return session_cookie
end

local function logout(session_cookie, admin_client)
  local res, err = admin_client:send {
    method = "GET",
    path = "/auth?openid_logout=true",
    headers = {
      Cookie = session_cookie,
    }
  }
  assert.is_nil(err)
  assert.equal(302, res.status)

  -- Ensure the session cookie is cleared via the Set-Cookie header
  local session_cleared = false
  for _, cookie in ipairs(assert(get_cookie_table(res))) do
    if startswith(cookie, "session=;") then
      session_cleared = true
      break
    end
  end
  assert.is_true(session_cleared)

  res, err = http:request_uri(res.headers["Location"], {
    method = "GET",
  })

  assert.is_nil(err)
  assert.equal(302, res.status)
  assert.equal(LOGOUT_REDIRECT_URL, res.headers["Location"])
end

local function compose_openid_conf(overrides)
  local conf = {
    issuer = cloak_settings.issuer,
    client_id = { cloak_settings.client_id },
    client_secret = { cloak_settings.client_secret },
    authenticated_groups_claim = { "groups" },
    admin_claim = "email",
    auth_methods = { "authorization_code", "session" },
    redirect_uri = { REDIRECT_URL },
    login_redirect_uri = { LOGIN_REDIRECT_URL },
    logout_methods = { "GET" },
    logout_query_arg = "openid_logout",
    logout_redirect_uri = { LOGOUT_REDIRECT_URL },
  }

  for key, value in pairs(overrides or {}) do
    conf[key] = value
  end

  return cjson.encode(conf)
end

local function check_ws_rbac(db, username, workspace, role)
  local admins, err = assert(db.admins:select_by_username(username))
  assert.is_nil(err)
  assert.is_not_nil(admins)
  assert(username, admins.username)

  local rbac_user_id = assert(admins.rbac_user and admins.rbac_user.id)

  local ws
  ws, err = db.workspaces:select_by_name(workspace)
  assert.is_nil(err)
  assert.is_not_nil(ws)

  local rbac_role
  rbac_role, err = db.rbac_roles:select_by_name(role, { workspace = ws.id })
  assert.is_nil(err)
  assert.is_not_nil(rbac_role)

  local rbac_user_roles
  rbac_user_roles, err = db.rbac_user_roles:select({
    user = { id = rbac_user_id },
    role = { id = rbac_role.id }
  })
  assert.is_nil(err)
  assert.is_not_nil(rbac_user_roles)
end

local function authenticate(db, admin_client, username)
  local res, auth_cookie = init_auth(admin_client, username, PASSWORD)
  -- Should be a 302 response to REDIRECT_URL
  assert.equal(302, res.status)

  local session_cookie = finalize_auth(assert(res.headers["Location"]), auth_cookie)

  local err
  res, err = assert(admin_client:send {
    method  = "GET",
    path    = "/userinfo",
    headers = {
      ['Cookie'] = session_cookie,
    }
  })
  assert.is_nil(err)

  -- Expect the new admin to be created
  local body = assert.res_status(200, res)
  local userinfo = cjson.decode(body)
  assert.equal(username, userinfo.admin.username)
  assert.is_not_nil(userinfo.session)

  local admins
  admins, err = assert(db.admins:select_by_username(username))
  assert.is_nil(err)
  assert.is_not_nil(admins)
  assert(username, admins.username)

  return session_cookie
end

local TEST_TABLES = {
  "admins",
  "plugins",
  "groups",
  "rbac_roles",
  "rbac_user_roles",
  "rbac_user_groups",
  "rbac_role_endpoints",
  "workspaces"
}

local function truncate_test_tables(db)
  for _, table_name in ipairs(TEST_TABLES) do
    db:truncate(table_name)
  end
end

for _, strategy in helpers.each_strategy() do
  describe("Admin auth API authentication on #" .. strategy, function()
    describe("#openid-connect - simple configuration", function ()
      local USERNAME = "john.doe@konghq.com"
      local WORKSPACE_NAME = "default"
      local ROLE_NAME = "super-admin"

      local _, db, admin_client

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, TEST_TABLES, { PLUGIN_NAME })

        assert(helpers.start_kong({
          plugins             = "bundled," .. PLUGIN_NAME,
          database            = strategy,
          nginx_conf          = "spec/fixtures/custom_nginx.template",
          enforce_rbac        = "on",
          admin_gui_auth      = PLUGIN_NAME,
          admin_listen        = ADMIN_API_LISTEN,
          admin_gui_listen    = ADMIN_GUI_LISTEN,
          admin_gui_auth_conf = cjson.encode({
            issuer = cloak_settings.issuer,
            client_id = { cloak_settings.client_id },
            client_secret = { cloak_settings.client_secret },
            authenticated_groups_claim = { "groups" },
            admin_claim = "email",
            redirect_uri = { REDIRECT_URL },
            login_redirect_uri = { LOGIN_REDIRECT_URL },
            logout_redirect_uri = { LOGOUT_REDIRECT_URL },
          }),
        }))

        ee_helpers.register_rbac_resources(db, "default")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        truncate_test_tables(db)
      end)

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("should log in successfully", function()
        -- Ensure there are no admins
        local admins, err = db.admins:select_by_username(USERNAME)
        assert.is_nil(err)
        assert.is_nil(admins)

        authenticate(db, admin_client, USERNAME)
        check_ws_rbac(db, USERNAME, WORKSPACE_NAME, ROLE_NAME)
      end)
    end)

    describe("#openid-connect - response_mode = query", function()
      local USERNAME = "john.doe@konghq.com"
      local WORKSPACE_NAME = "default"
      local ROLE_NAME = "super-admin"

      local _, db, admin_client, session_cookie

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, TEST_TABLES, { PLUGIN_NAME })

        assert(helpers.start_kong({
          plugins             = "bundled," .. PLUGIN_NAME,
          database            = strategy,
          nginx_conf          = "spec/fixtures/custom_nginx.template",
          enforce_rbac        = "on",
          admin_gui_auth      = PLUGIN_NAME,
          admin_listen        = ADMIN_API_LISTEN,
          admin_gui_listen    = ADMIN_GUI_LISTEN,
          admin_gui_auth_conf = compose_openid_conf(),
        }))

        ee_helpers.register_rbac_resources(db, "default")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        truncate_test_tables(db)
      end)

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("should log in successfully and map to the correct role", function()
        -- Ensure there are no admins
        local admins, err = db.admins:select_by_username(USERNAME)
        assert.is_nil(err)
        assert.is_nil(admins)

        session_cookie = authenticate(db, admin_client, USERNAME)
        check_ws_rbac(db, USERNAME, WORKSPACE_NAME, ROLE_NAME)
      end)

      it("should perform RP-initiated logout", function()
        logout(session_cookie, admin_client)
      end)
    end)

    describe("#openid-connect - response_mode = form_post", function()
      local USERNAME = "john.doe@konghq.com"

      local _, db, admin_client, session_cookie

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, TEST_TABLES, { PLUGIN_NAME })

        assert(helpers.start_kong({
          plugins             = "bundled," .. PLUGIN_NAME,
          database            = strategy,
          prefix              = helpers.test_conf.prefix,
          enforce_rbac        = "on",
          admin_gui_auth      = PLUGIN_NAME,
          admin_listen        = ADMIN_API_LISTEN,
          admin_gui_listen    = ADMIN_GUI_LISTEN,
          admin_gui_auth_conf = compose_openid_conf { response_mode = "form_post" },
        }))

        ee_helpers.register_rbac_resources(db, "default")
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        truncate_test_tables(db)
      end)

      before_each(function()
        admin_client = helpers.admin_client()
      end)

      after_each(function()
        if admin_client then
          admin_client:close()
        end
      end)

      it("should log in successfully", function()
        -- Ensure there are no admins
        local admins, err = db.admins:select_by_username(USERNAME)
        assert.is_nil(err)
        assert.is_nil(admins)

        -- begin auth via openid-connect
        local res, auth_cookie = init_auth(admin_client, USERNAME, PASSWORD)
        -- Should be a 200 response
        assert.equal(200, res.status)

        -- Extract the action URL and parameters from the <form /> element
        local action_start_t = [[<FORM METHOD="POST" ACTION="]]
        local action_start = assert(find(res.body, action_start_t, 1, true))
        local action_end = assert(find(res.body, [["]], action_start + #action_start_t, true))

        local field_names = {
          "code",
          "state",
          "session_state",
        }
        local fields = {}
        local field_start_t, field_start, field_end
        for _, name in ipairs(field_names) do
          field_start_t = [[NAME="]] .. name .. [[" VALUE="]]
          field_start = assert(find(res.body, field_start_t, action_end, true))
          field_end = assert(find(res.body, [["]], field_start + #field_start_t, true))

          table.insert(fields, name .. "=" .. sub(res.body, field_start + #field_start_t, field_end - 1))
        end

        local action = sub(res.body, action_start + #action_start_t, action_end - 1)
        assert.equal(REDIRECT_URL, action)

        session_cookie = finalize_auth(action, auth_cookie, table.concat(fields, "&"))
      end)

      it("should perform RP-initiated logout", function()
        logout(session_cookie, admin_client)
      end)
    end)

    describe("#openid-connect - mapping role with group", function()
      local USERNAME = "sam.stark@konghq.com"

      local _, db, admin_client, keycloak_client
      local user, group_ws1, group_ws2, default_super_admin_group

      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, TEST_TABLES, { PLUGIN_NAME })

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
          admin_gui_auth_conf    = compose_openid_conf(),
        }))

        ee_helpers.register_rbac_resources(db, "default")
        admin_client = helpers.admin_client()
        keycloak_client = helpers.http_client(cloak_settings.ip, cloak_settings.port)

        -- retrieve user from keycloak
        user = get_user_by_username(keycloak_client, "sam")
        -- default_super_admin_group = get_group_by_name(keycloak_client, "default:super-admin")
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
        truncate_test_tables(db)

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
        -- Ensure there are no admins
        local admins, err = db.admins:select_by_username(USERNAME)
        assert.is_nil(err)
        assert.is_nil(admins)

        authenticate(db, admin_client, USERNAME)

        -- login success
        local admin = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admin.username)
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

      -- FIXME: Disabling this test case as we reverted some fixes on RBAC roles
      -- See: https://github.com/Kong/kong-ee/pull/8060
      --
      -- it("the admin has all workspaces permissions when add the group `default:super-admin` of IDP", function()
      --   -- add default:super-admin to admin
      --   do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id,
      --     default_super_admin_group.id)
      --   authenticate(db, admin_client, USERNAME)
      --   -- login success
      --   local admin = db.admins:select_by_username(USERNAME)
      --   assert(USERNAME, admin.username)
      --   local rbac_user_id = admin.rbac_user and admin.rbac_user.id
      --   assert.is_not_nil(rbac_user_id)
      --   local user_token = update_rbac_token(rbac_user_id)

      --   -- should access ws1/services
      --   for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
      --     local res = assert(admin_client:send {
      --       method = "GET",
      --       path = "/" .. ws_name .. "/services",
      --       headers = {
      --         ["Kong-Admin-Token"] = user_token
      --       }
      --     })
      --     assert.response(res).has.status(200)
      --   end
      -- end)

      it("the admin has readonly permissions of the workspace ws1 when add the group `readonly_group_ws1` of IDP", function()
        -- remove default:super-admin from the admin

        -- FIXME: Commenting this line as we reverted some fixes on RBAC roles
        -- See: https://github.com/Kong/kong-ee/pull/8060
        -- do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, default_super_admin_group.id)
        --
        -- add readonly_group_ws1 to the admin
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id, group_ws1.id)
        -- begin auth via openid-connect
        authenticate(db, admin_client, USERNAME)
        -- login success
        local admin = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admin.username)
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
        authenticate(db, admin_client, USERNAME)
        -- login success
        local admin = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admin.username)
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
        authenticate(db, admin_client, USERNAME)
        -- login success
        local admin = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admin.username)
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

      -- FIXME: Commenting this line as we reverted some fixes on RBAC roles
      -- See: https://github.com/Kong/kong-ee/pull/8060
      -- do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, default_super_admin_group.id)
      --
      -- it("the admin doesn't have any permissions when remove the group `readonly_group_ws2` of IDP", function()
      --   do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, group_ws2.id)
      --
      --   -- begin auth via openid-connect
      --   authenticate(db, admin_client, USERNAME)
      --   -- login success
      --   local admin = db.admins:select_by_username(USERNAME)
      --   assert(USERNAME, admin.username)
      --   local rbac_user_id = admin.rbac_user and admin.rbac_user.id
      --   assert.is_not_nil(rbac_user_id)

      --   local user_token = update_rbac_token(rbac_user_id)

      --   local rbac_user_groups = {}
      --   for rbac_user_group, _ in db.rbac_user_groups:each_for_user({ id = rbac_user_id }) do
      --     table.insert(rbac_user_groups, rbac_user_group)
      --   end
      --   assert.equal(0, #rbac_user_groups)
      --   for _, ws in ipairs({ "ws1", "ws2", "default" }) do
      --     -- should access ws1/services
      --     local res = assert(admin_client:send {
      --       method = "GET",
      --       path = "/" .. ws .. "/services",
      --       headers = {
      --         ["Kong-Admin-Token"] = user_token
      --       }
      --     })
      --     assert.response(res).has.status(403)
      --   end
      -- end)

      it("the admin doesn't have any permissions when delete group `readonly_group_ws2`", function()
        do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id, group_ws2.id)

        -- begin auth via openid-connect
        authenticate(db, admin_client, USERNAME)
        -- login success
        local admin = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admin.username)
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
        authenticate(db, admin_client, USERNAME)

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

      -- FIXME: Commenting this line as we reverted some fixes on RBAC roles
      -- See: https://github.com/Kong/kong-ee/pull/8060
      -- do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id, default_super_admin_group.id)
      --
      -- it("the admin should doesn't have any permissions when remove the group `default:super-admin` again", function()
      --   -- add default:super-admin to admin
      --   do_cloak_request(keycloak_api.add_group_to_user, keycloak_client, false, 204, user.id,
      --     default_super_admin_group.id)
      --   authenticate(db, admin_client, USERNAME)
      --   -- login success
      --   local admin = db.admins:select_by_username(USERNAME)
      --   assert(USERNAME, admin.username)
      --   local rbac_user_id = admin.rbac_user and admin.rbac_user.id
      --   assert.is_not_nil(rbac_user_id)
      --   local user_token = update_rbac_token(rbac_user_id)

      --   -- should access ws1/services
      --   for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
      --     local res = assert(admin_client:send {
      --       method = "GET",
      --       path = "/" .. ws_name .. "/services",
      --       headers = {
      --         ["Kong-Admin-Token"] = user_token
      --       }
      --     })
      --     assert.response(res).has.status(200)
      --   end

      --   -- remove default:super-admin from admin
      --   do_cloak_request(keycloak_api.delete_group_from_user, keycloak_client, false, 204, user.id,
      --     default_super_admin_group.id)
      --   authenticate(db, admin_client, USERNAME)
      --   -- login success

      --   -- should access ws1/services
      --   for _, ws_name in ipairs({ "ws1", "ws2", "default" }) do
      --     local res = assert(admin_client:send {
      --       method = "GET",
      --       path = "/" .. ws_name .. "/services",
      --       headers = {
      --         ["Kong-Admin-Token"] = user_token
      --       }
      --     })
      --     assert.response(res).has.status(403)
      --   end
      -- end)
    end)
  end)
end
