-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers             = require "spec.helpers"
local ee_helpers          = require "spec-ee.helpers"
local pl_path             = require "pl.path"
local pl_file             = require "pl.file"
local sub                 = string.sub
local find                = string.find
local fmt                 = string.format

local cookie_helper       = require "spec-ee.fixtures.cookie_helper"
local clear_license_env   = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local portal_client
local PLUGIN_NAME         = "openid-connect"
local KEYCLOAK_HOST       = (os.getenv("KONG_SPEC_TEST_KEYCLOAK_HOST") or "keycloak") .. ":" .. (os.getenv("KONG_SPEC_TEST_KEYCLOAK_PORT_8080") or "8080")
local ISSUER_URL          = fmt("http://%s/realms/demo/", KEYCLOAK_HOST)
local USERNAME            = "john.doe@konghq.com"
local PASSWORD            = "doe"
local KONG_CLIENT_ID      = "kong-client-secret"
local KONG_CLIENT_SECRET  = "38beb963-2786-42b8-8e14-a5f391b4ba93"
local KONG_HOST           = "localhost"

local PORTAL_SESSION_CONF = [[
    {
      "cookie_name":"portal_session",
      "secret":"super-secret",
      "cookie_secure":false,
      "cookie_path":"/default",
      "storage":"kong"
    }
  ]]

local function auth_conf(workspace)
  local login_redirect_uri = fmt("http://%s:%d/%s", KONG_HOST, ee_helpers.get_portal_gui_port(), workspace)
  local redirect_uri       = fmt("http://%s:%d/%s/auth", KONG_HOST, ee_helpers.get_portal_api_port(), workspace)

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
      "consumer_claim": [
          "email"
      ]
    }
  ]]
end

local function close_clients(clients)
  for _, client in ipairs(clients) do
    client:close()
  end
end

local function create_portal_index()
  local prefix = kong.configuration and kong.configuration.prefix or 'servroot/'
  local portal_dir = 'portal'
  local portal_path = prefix .. "/" .. portal_dir
  local views_path = portal_path .. '/views'
  local index_filename = views_path .. "/index.etlua"
  local index_str =
  "<% for key, value in pairs(configs) do %>  <meta name=\"KONG:<%= key %>\" content=\"<%= value %>\" /><% end %>"

  if not pl_path.exists(portal_path) then
    pl_path.mkdir(portal_path)
  end

  if not pl_path.exists(views_path) then
    pl_path.mkdir(views_path)
  end

  pl_file.write(index_filename, index_str)
end

local function configure_portal(db, workspace, config)
  db.workspaces:upsert_by_name(workspace, {
    name = workspace,
    config = config,
  })
end

local function authentication(workspace)
  local res = assert(portal_client:send {
    method = "GET",
    path = fmt("/%s/session", workspace),
  })

  assert.response(res).has.status(302)
  local redirect = res.headers["Location"]
  -- get authorization=...; cookie
  local auth_cookie = res.headers["Set-Cookie"]
  local auth_cookie_cleaned = sub(auth_cookie, 0, find(auth_cookie, ";") - 1)
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

  local keycloak_cookie_jar = cookie_helper.CookieManager:new()
  local set_cookies_header = assert.response(rres).has.header("Set-Cookie")
  keycloak_cookie_jar:parse_set_cookie_headers(set_cookies_header)

  -- get the action_url from submit button and post username:password
  local action_start = find(rres.body, 'action="', 0, true)
  local action_end = find(rres.body, '"', action_start + 8, true)
  local login_button_url = string.sub(rres.body, action_start + 8, action_end - 1)
  -- the login_button_url is endcoded. decode it
  login_button_url = string.gsub(login_button_url, "&amp;", "&")
  -- build form_data
  local form_data = "username=" .. USERNAME .. "&password=" .. PASSWORD .. "&credentialId="
  local opts = {
    method = "POST",
    body = form_data,
    headers = {
      -- impersonate as browser
      ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", --luacheck: ignore
      ["Host"] = KEYCLOAK_HOST,
      -- due to form_data
      ["Content-Type"] = "application/x-www-form-urlencoded",
      Cookie = keycloak_cookie_jar:to_header(),
    }
  }
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

  local portal_cookie_jar = cookie_helper.CookieManager:new()

  -- extract final redirect
  local final_url = ures.headers["Location"]
  set_cookies_header = assert.response(ures).has.header("Set-Cookie")
  portal_cookie_jar:parse_set_cookie_headers(set_cookies_header)

  return final_url, portal_cookie_jar
end

for _, strategy in helpers.each_strategy() do
  describe("Dev portal enable openid-connect on strategy=#" .. strategy, function()
    for _, workspace in ipairs({ "default", "demo" }) do
      describe("With the workspace is " .. workspace, function()
        local db
        local reset_license_data
        lazy_setup(function()
          reset_license_data = clear_license_env()
          db = select(2, helpers.get_db_utils(strategy, {
            "consumers",
            "plugins",
          }, { PLUGIN_NAME }))

          assert(helpers.start_kong({
            plugins             = "bundled," .. PLUGIN_NAME,
            database            = strategy,
            nginx_conf          = "spec/fixtures/custom_nginx.template",
            portal              = true,
            portal_auth         = PLUGIN_NAME,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_cors_origins = "*",
            license_path = "spec-ee/fixtures/mock_license.json",
            portal_and_vitals_key = get_portal_and_vitals_key(),
          }))

          if workspace ~= "default" then
            assert(db.workspaces:insert({ name = workspace }))
          end
          create_portal_index()

          configure_portal(db, workspace, {
            portal = true,
            portal_auth = PLUGIN_NAME,
            portal_auth_conf = auth_conf(workspace),
            portal_is_legacy = true,
            portal_auto_approve = true,
          })
        end)

        lazy_teardown(function()
          helpers.stop_kong()
          reset_license_data()
        end)

        before_each(function()
          portal_client = ee_helpers.portal_api_client()
        end)

        after_each(function()
          close_clients(portal_client)
        end)

        it("Developers register and log in to the dev portal", function()
          local _, auth_cookie = authentication(workspace)
          -- register developer
          local res, err = assert(portal_client:send {
            method = "POST",
            path = fmt("/%s/register", workspace),
            body = {
              meta = "{\"full_name\":\"john.doe\"}",
              email = "john.doe@konghq.com"
            },
            headers = {
              ["Content-Type"] = "application/json",
              -- send session cookie
              ["Cookie"] = auth_cookie:to_header()
            }
          })
          assert.is_nil(err)
          assert.equal(200, res.status)
        end)

        it("After the registered developer logs in successfully should be retrieved session well", function()
          local _, auth_cookie = authentication(workspace)

          -- retrieve session
          local session_res, session_err = portal_client:send {
            method = "GET",
            path = "/" .. workspace .. "/session",
            headers = {
              -- send session cookie
              ["Cookie"] = auth_cookie:to_header()
            }
          }
          assert.equal(200, session_res.status)
          assert.is_nil(session_err)
        end)
      end)
    end
  end)
end
