-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local sub = string.sub
local find = string.find

local admin_client
local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak:8080"
local ISSUER_URL = "http://" .. KEYCLOAK_HOST .. "/realms/demo/"
local USERNAME = "john.doe@konghq.com"
local PASSWORD = "doe"
local KONG_CLIENT_ID = "kong-client-secret"
local KONG_CLIENT_SECRET = "38beb963-2786-42b8-8e14-a5f391b4ba93"
local KONG_HOST = "kong"
local WORKSPACE_NAME = "default"
local ROLE_NAME = "super-admin"

local function authentication()
  local res = assert(admin_client:send {
    method = "POST",
    path = "/auth",
  })

  assert.response(res).has.status(302)
  local redirect = res.headers["Location"]
  -- get authorization=...; cookie
  local auth_cookie = res.headers["Set-Cookie"]
  local auth_cookie_cleaned = sub(auth_cookie, 0, find(auth_cookie, ";") -1)
  local http = require "resty.http".new()
  local rres, err = http:request_uri(redirect, {
    headers = {
      -- impersonate as browser
      ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", -- luacheck: ignore
      ["Host"] = KEYCLOAK_HOST,
    }
  })
  assert.is_nil(err)
  assert.equal(200, rres.status)

  local cookies = rres.headers["Set-Cookie"]
  local user_session
  local user_session_header_table = {}
  for _, cookie in ipairs(cookies) do
    user_session = sub(cookie, 0, find(cookie, ";") -1)
    if find(user_session, 'AUTH_SESSION_ID=', 1, true) ~= 1 then
      -- auth_session_id is dropped by the browser for non-https connections
      table.insert(user_session_header_table, user_session)
    end
  end
  -- get the action_url from submit button and post username:password
  local action_start = find(rres.body, 'action="', 0, true)
  local action_end = find(rres.body, '"', action_start+8, true)
  local login_button_url = string.sub(rres.body, action_start+8, action_end-1)
  -- the login_button_url is endcoded. decode it
  login_button_url = string.gsub(login_button_url,"&amp;", "&")
  -- build form_data
  local form_data = "username="..USERNAME.."&password="..PASSWORD.."&credentialId="
  local opts = { method = "POST",
    body = form_data,
    headers = {
      -- impersonate as browser
      ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", --luacheck: ignore
      ["Host"] = KEYCLOAK_HOST,
      -- due to form_data
      ["Content-Type"] = "application/x-www-form-urlencoded",
      Cookie = user_session_header_table,
  }}
  local loginres
  loginres, err = http:request_uri(login_button_url, opts)
  assert.is_nil(err)
  assert.equal(302, loginres.status)

  -- after sending login data to the login action page, expect a redirect
  local upstream_url = loginres.headers["Location"]
  local ures
  ures, err = http:request_uri(upstream_url, {
    headers = {
      -- authenticate using the cookie from the initial request
      Cookie = auth_cookie_cleaned,
    }
  })
  assert.is_nil(err)
  assert.equal(200, ures.status)
end

for _, strategy in helpers.each_strategy() do
  describe("Admin auth API authentication on #" .. strategy, function()
    describe("#openid-connect - authentication", function()
      local _, db
      lazy_setup(function()
        _, db = helpers.get_db_utils(strategy, {
          "admins",
          "plugins",
        }, { PLUGIN_NAME })

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
          admin_gui_auth_conf   = [[
            {
              "issuer": "]]..ISSUER_URL..[[",
              "preserve_query_args": false,
              "consumer_claim": [
                  "email"
              ],
              "admin_claim": "email",
              "client_id": [
                  "]]..KONG_CLIENT_ID..[["
              ],
              "client_secret": [
                  "]]..KONG_CLIENT_SECRET..[["
              ],
              "authenticated_groups_claim": [
                  "groups"
              ],
              "ssl_verify": false,
              "leeway": 60,
              "redirect_uri": [
                  "http://]]..KONG_HOST..[[:9001/auth"
              ],
              "login_redirect_uri": [
                  "http://]]..KONG_HOST..[[:9001/userinfo"
              ],
              "logout_methods": [
                  "GET",
                  "DELETE"
              ],
              "logout_query_arg": "logout",
              "logout_redirect_uri": [
                  "http://]]..KONG_HOST..[[:9001/"
              ],
              "auth_methods": [
                  "authorization_code",
                  "session"
              ]
            }
          ]]
        }))

        local default_ws = db.workspaces:select_by_name(WORKSPACE_NAME)
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
        -- begin auth via openid-connect
        authentication()
        -- login success
        local admins = db.admins:select_by_username(USERNAME)
        assert(USERNAME, admins.username)
        local rbac_user_id = admins.rbac_user and admins.rbac_user.id
        assert.is_not_nil(rbac_user_id)
        local ws = db.workspaces:select_by_name(WORKSPACE_NAME)
        local role = assert(db.rbac_roles:select_by_name(ROLE_NAME, { workspace = ws.id }))
        local rbac_user_roles = assert(db.rbac_user_roles:select({
          user = { id = rbac_user_id },
          role = { id = role.id }
        }))
        assert.is_not_nil(rbac_user_roles)
      end)
    end)
  end)
end