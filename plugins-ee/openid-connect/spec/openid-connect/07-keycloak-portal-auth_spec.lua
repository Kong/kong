-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local sub = string.sub
local find = string.find

local portal_client
local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak:8080"
local ISSUER_URL = "http://" .. KEYCLOAK_HOST .. "/auth/realms/demo/"
local USERNAME = "john.doe@konghq.com"
local PASSWORD = "doe"
local KONG_CLIENT_ID = "kong-client-secret"
local KONG_CLIENT_SECRET = "38beb963-2786-42b8-8e14-a5f391b4ba93"
local KONG_HOST ="kong"

local function auth_conf()
  local login_redirect_uri  = "http://"..KONG_HOST..":"..ee_helpers.get_portal_gui_port()
  local redirect_uri = "http://"..KONG_HOST..":"..ee_helpers.get_portal_api_port() .."/default/auth"
  return [[
    {
    "redirect_uri": ["]]
      .. redirect_uri ..
      [["],
      "client_secret": ["]]
      .. KONG_CLIENT_SECRET ..
      [["],
      "issuer": "]]
      .. ISSUER_URL ..
      [[",
      "logout_methods": [
          "GET",
          "DELETE"
      ],
      "logout_query_arg": "logout",
      "by_username_ignore_case": true,
      "logout_redirect_uri": ["]]
      .. login_redirect_uri ..
      [["],
      "scopes": [
          "openid",
          "profile",
          "email",
          "offline_access"
      ],
      "authenticated_groups_claim": [
          "groups"
      ],
      "login_redirect_uri": ["]]
      .. login_redirect_uri ..
      [["],
      "leeway": 60,
      "auth_methods": [
          "authorization_code",
          "session"
      ],
      "client_id": ["]]
      .. KONG_CLIENT_ID ..
          [["],
      "ssl_verify": false,
      "by_username_ignore_case":true,
      "consumer_claim": [
          "email"
      ]
    }
  ]]
end

local function configure_portal(db, config)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config,
  })
end

local function authentication()
  local res = assert(portal_client:send {
    method = "GET",
    path = "/default/session",
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
      Cookie = auth_cookie_cleaned
    }
  })
  assert.is_nil(err)
  assert.equal(302, ures.status)
  local client_session
  local client_session_header_table = {}
  -- extract session cookies
  local ucookies = ures.headers["Set-Cookie"]
  -- extract final redirect
  local final_url = ures.headers["Location"]
  for i, cookie in ipairs(ucookies) do
    client_session = sub(cookie, 0, find(cookie, ";") -1)
    client_session_header_table[i] = client_session
  end
  return final_url,client_session_header_table
end

for _, strategy in helpers.each_strategy() do
  describe("Dev portal API authentication on #" .. strategy, function()
    describe("#openid-connect - authentication", function()
      lazy_setup(function()
        local _, db = helpers.get_db_utils(strategy, {
          "consumers",
          "plugins",
        }, { PLUGIN_NAME })

        assert(helpers.start_kong({
          plugins                = "bundled," .. PLUGIN_NAME,
          database               = strategy,
          nginx_conf             = "spec/fixtures/custom_nginx.template",
          portal                 = true,
          portal_auth            = PLUGIN_NAME,
          portal_gui_protocol    = "http",
          portal_cors_origins    = "*"
        }))

        configure_portal(db, {
          portal = true,
          portal_auth = PLUGIN_NAME,
          portal_auth_conf = auth_conf(),
          portal_is_legacy = true,
          portal_auto_approve = true,
        })
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        portal_client = ee_helpers.portal_api_client()
      end)

      after_each(function()
        if portal_client then
          portal_client:close()
        end
      end)

      describe("dev portal login with oidc when [by_username_ignore_case=true]", function ()
        it("The new developer first login dev portal needs to register", function()
          local url, client_session_header_table = authentication()
          assert.same("http://127.0.0.1:9003/default/register", url)
          local ures_final, err = portal_client:send {
            method = "POST",
            path = "/default/register",
            body = {
              meta = "{\"full_name\":\"john.doe\"}",
              email = "john.doe@konghq.com"
            },
            headers = {
              ["Content-Type"] = "application/json",
              -- send session cookie
              Cookie = client_session_header_table
            }
          }
          assert.is_nil(err)
          assert.equal(200, ures_final.status)
        end)

        it("The same developer =" .. USERNAME .. " login again successfual login dev portal",function ()
          local url = authentication()
          local login_redirect_uri  = "http://"..KONG_HOST..":"..ee_helpers.get_portal_gui_port()
          assert.same(login_redirect_uri, url)
        end)
      end)
    end)
  end)
end