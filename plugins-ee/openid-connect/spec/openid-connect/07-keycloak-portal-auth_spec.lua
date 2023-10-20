-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local cookie_helper = require "spec-ee.fixtures.cookie_helper"
local find = string.find
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key

local portal_client
local PLUGIN_NAME = "openid-connect"
local KEYCLOAK_HOST = "keycloak:8080"
local ISSUER_URL = "http://" .. KEYCLOAK_HOST .. "/realms/demo/"
local USERNAME = "john.doe@konghq.com"
local PASSWORD = "doe"
local KONG_CLIENT_ID = "kong-client-secret"
local KONG_CLIENT_SECRET = "38beb963-2786-42b8-8e14-a5f391b4ba93"
local KONG_HOST ="localhost"

local function auth_conf(workspace_name, subdomain_mode, mixin)
  local login_redirect_uri = subdomain_mode
    and "http://" .. workspace_name .. "." .. KONG_HOST .. ":" .. ee_helpers.get_portal_gui_port()
    or "http://" .. KONG_HOST .. ":" .. ee_helpers.get_portal_gui_port() .. "/" .. workspace_name

  local redirect_uri =
    "http://" .. KONG_HOST .. ":" .. ee_helpers.get_portal_api_port() .. "/" .. workspace_name .. "/auth"

  local conf = {
    redirect_uri = { redirect_uri },
    client_secret = { KONG_CLIENT_SECRET },
    issuer = ISSUER_URL,
    logout_methods = { "GET", "DELETE" },
    logout_query_arg = "logout",
    logout_redirect_uri = { login_redirect_uri },
    scopes = { "openid", "profile", "email", "offline_access" },
    authenticated_groups_claim = { "groups" },
    login_redirect_uri = { login_redirect_uri },
    leeway = 60,
    auth_methods = { "authorization_code", "session" },
    client_id = { KONG_CLIENT_ID },
    ssl_verify = false,
    consumer_claim = { "email" }
  }

  for k, v in pairs(mixin or {}) do
    conf[k] = v
  end

  return cjson.encode(conf), conf
end

local function configure_portal(db, workspace_name, config)
  db.workspaces:upsert_by_name(workspace_name, {
    name = workspace_name,
    config = config,
  })
end

local function admin_client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()

  client:close()
  return res
end

local function authentication(workspace_name)
  local portal_cookie_jar = cookie_helper.CookieManager:new()
  local keycloak_cookie_jar = cookie_helper.CookieManager:new()

  local res = assert(portal_client:send {
    method = "GET",
    path = "/" .. workspace_name .. "/session",
  })
  assert.response(res).has.status(302)
  portal_cookie_jar:parse_set_cookie_headers(res.headers["Set-Cookie"])

  local http = require "resty.http".new()
  local redirect = res.headers["Location"]
  local rres, err = http:request_uri(redirect, {
    headers = {
      -- impersonate as browser
      ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", -- luacheck: ignore
      ["Host"] = KEYCLOAK_HOST,
    }
  })
  assert.is_nil(err)
  assert.equal(200, rres.status)

  keycloak_cookie_jar:parse_set_cookie_headers(rres.headers["Set-Cookie"])

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
      Cookie = keycloak_cookie_jar:to_header(),
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
      Cookie = portal_cookie_jar:to_header()
    }
  })
  assert.is_nil(err)
  assert.equal(302, ures.status)

  -- extract final redirect
  local final_url = ures.headers["Location"]
  portal_cookie_jar:parse_set_cookie_headers(ures.headers["Set-Cookie"])

  return final_url,portal_cookie_jar
end

-- for db strategy
for _, strategy in helpers.each_strategy() do
  describe("#openid-connect Dev portal GUI and API authentication on #" .. strategy, function()
    -- for subdomain or secondary path
    for _, use_subdomain_for_workspace in ipairs({ false, true }) do
      -- for different workspace
      for _, workspace_name in ipairs({ "default", "demo" }) do
        -- for by_username_ignore_case
        for _, by_username_ignore_case in ipairs({ false, true }) do
          local description = "with workspace #" .. workspace_name .. " " ..
            (use_subdomain_for_workspace and "in #subdomain" or "in #secondary-path") .. " &"

          describe(description, function()
            local db
            local workspace_gui_path = use_subdomain_for_workspace and "/" or "/" .. workspace_name
            local reset_license_data

            lazy_setup(function()
              reset_license_data = clear_license_env()
              db = select(2, helpers.get_db_utils(strategy, {
                "consumers",
                "plugins",
                "workspaces"
              }, { PLUGIN_NAME }))

              assert(helpers.start_kong({
                plugins                = "bundled," .. PLUGIN_NAME,
                database               = strategy,
                nginx_conf             = "spec/fixtures/custom_nginx.template",
                portal                 = true,
                portal_auth            = PLUGIN_NAME,
                portal_cors_origins    = "*",
                portal_gui_protocol    = "http",
                portal_gui_host        = KONG_HOST .. ":9003",
                portal_gui_use_subdomains = use_subdomain_for_workspace,
                portal_and_vitals_key = get_portal_and_vitals_key(),
                license_path = "spec-ee/fixtures/mock_license.json",
              }))

              if workspace_name ~= "default" then
                assert(db.workspaces:insert({ name = workspace_name }))
              end
            end)

            lazy_teardown(function()
              helpers.stop_kong()
              reset_license_data()
            end)

            before_each(function()
              portal_client = ee_helpers.portal_api_client()
            end)

            after_each(function()
              if portal_client then
                portal_client:close()
              end
            end)

            describe("by_username_ignore_case=#" .. tostring(by_username_ignore_case), function ()
              lazy_setup(function()
                configure_portal(db, workspace_name, {
                  portal = true,
                  portal_auth = PLUGIN_NAME,
                  portal_auth_conf = auth_conf(workspace_name, use_subdomain_for_workspace, {
                    by_username_ignore_case = by_username_ignore_case
                  }),
                  portal_is_legacy = true,
                  portal_auto_approve = true,
                })
              end)

              it("should require registration on the first time login from a new developer", function()
                local url, client_session_header_table = authentication(workspace_name)
                local expected_url = use_subdomain_for_workspace
                  and "http://" .. workspace_name .. "." .. KONG_HOST .. ":9003/register"
                  or "http://" .. KONG_HOST .. ":9003/" .. workspace_name .. "/register"
                assert.same(expected_url, url)
                local ures_final, err = portal_client:send {
                  method = "POST",
                  path = "/" .. workspace_name .. "/register",
                  body = {
                    meta = "{\"full_name\":\"john.doe\"}",
                    email = "john.doe@konghq.com"
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    -- send session cookie
                    Cookie = client_session_header_table:to_header()
                  }
                }
                assert.is_nil(err)
                assert.equal(200, ures_final.status)
              end)

              it("should login successfully when developer " .. USERNAME .. " is already registered",function ()
                local url = authentication(workspace_name)
                local expected_url = use_subdomain_for_workspace
                  and "http://" .. workspace_name .. "." .. KONG_HOST .. ":9003"
                  or "http://" .. KONG_HOST .. ":9003/" .. workspace_name .. ""
                assert.same(expected_url, url)
              end)

              it("should be able to set correct cookie name and path when using default config", function ()
                local _, cookie_jar = authentication(workspace_name)
                local cookie = cookie_jar:get("session")
                assert(cookie)
                assert.same(workspace_gui_path, cookie.path)
              end)

              local session_cookie_path_table = {
                { config_path = "/", expected_path = "/" },
                { config_path = "/kong", expected_path = "/kong" },
                { config_path = "/kong/", expected_path = "/kong" },
                { config_path = "/kong/portal", expected_path = "/kong/portal" },
                { config_path = "/kong/portal/", expected_path = "/kong/portal" },
              }

              for _, cookie_path in ipairs(session_cookie_path_table) do
                local expected_path = use_subdomain_for_workspace
                  and cookie_path.config_path   -- we will leave session_cookie_path as is in subdomain mode
                  or (cookie_path.expected_path == "/" and "" or cookie_path.expected_path) .. "/" .. workspace_name

                local test_description = "should be able to set correct cookie name and path" ..
                  "when using custom config - " .. cookie_path.config_path .. "->" .. expected_path

                it(test_description, function ()
                  ee_helpers.register_rbac_resources(db)
                  local opt = {
                    override_default_headers = {
                      ["Kong-Admin-Token"] = "letmein-default",
                      ["Content-Type"] = "application/json",
                    },
                    disable_ipv6 = true,
                  }

                  local _, portal_auth_conf = auth_conf(workspace_name, use_subdomain_for_workspace, {
                    session_cookie_name = "my_session_cookie",
                    session_cookie_path = cookie_path.config_path,
                    by_username_ignore_case = by_username_ignore_case,
                  })

                  assert(admin_client_request({
                    method = "PATCH",
                    path = "/workspaces/" .. workspace_name,
                    body = {
                      config = {
                        portal = true,
                        portal_auth = PLUGIN_NAME,
                        portal_auth_conf = portal_auth_conf,
                        portal_is_legacy = true,
                        portal_auto_approve = true,
                      }
                    },
                    headers = {
                      ["Content-Type"] = "application/json",
                    }
                  }))

                  helpers.wait_for_all_config_update(opt)

                  local _, cookie_jar = authentication(workspace_name)
                  local cookie = cookie_jar:get("my_session_cookie")

                  assert(cookie)
                  assert.same(expected_path, cookie.path)
                end)
              end
            end)
          end)
        end
      end
    end
  end)
end
