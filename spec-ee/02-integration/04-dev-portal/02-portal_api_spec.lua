-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers      = require "spec.helpers"
local cjson        = require "cjson"
local enums        = require "kong.enterprise_edition.dao.enums"
local utils        = require "kong.tools.utils"
local ee_jwt       = require "kong.enterprise_edition.jwt"
local time         = ngx.time
local uuid         = require("kong.tools.utils").uuid
local ee_helpers   = require "spec-ee.helpers"
local type         = type
local clear_license_env = require("spec-ee.02-integration.04-dev-portal.utils").clear_license_env

local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"
local DEFAULT_CONSUMER = {
  ["basic-auth"] = {
    headers = {
      ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:Kong-Strong"),
    },
    body = {
      email = "gruce@konghq.com",
      password = "Kong-Strong",
      meta = "{\"full_name\":\"I Like Turtles\"}",
    },
  },
  ["key-auth"] = {
    headers = {
      ["apikey"] = "kongboi",
    },
    body = {
      email = "gruce@konghq.com",
      key = "kongboi",
      meta = "{\"full_name\":\"I Like Turtles\"}",
    },
  },
}

local function insert_files(db)
  for i = 1, 10 do
    local file_name = "file-" .. i
    assert(db.legacy_files:insert({
      name = file_name,
      contents = "i-" .. i,
      type = "partial",
      auth = i % 2 == 0 and true or false,
    }))

    local file_page_name = "file-page" .. i
    assert(db.legacy_files:insert({
      name = file_page_name,
      contents = "i-" .. i,
      type = "page",
      auth = i % 2 == 0 and true or false,
    }))
  end
end


local function register_developer(portal_api_client, body)
  if type(body) == "string" then
    body = DEFAULT_CONSUMER[body].body
  end

  return assert(portal_api_client:send {
    method = "POST",
    path = "/register",
    body = body,
    headers = {["Content-Type"] = "application/json"},
  })
end


local function authenticate(portal_api_client, headers, return_cookie)
  if type(headers) == "string" then
    headers = DEFAULT_CONSUMER[headers].headers
  end

  local res = assert(portal_api_client:send {
    method = "GET",
    path = "/auth",
    headers = headers
  })

  if return_cookie then
    assert.res_status(200, res)
    return assert.response(res).has.header("Set-Cookie")
  end

  return res
end


local function configure_portal(db, config)
  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config,
  })
end


local function close_clients(portal_api_client)
  if portal_api_client then
    portal_api_client:close()
  end
end


local function admin_client_request(params)
  local client = assert(helpers.admin_client())
  local res = assert(client:send(params))
  res.body = res:read_body()

  client:close()
  return res
end


local rbac_mode = {"off", "on"}

for _, strategy in helpers.each_strategy() do
  for idx, rbac in ipairs(rbac_mode) do
    describe("Developer Portal - Portal API #" .. strategy .. " (ENFORCE_RBAC = " .. rbac .. ")", function()
      local portal_api_client
      local _, db, _ = helpers.get_db_utils(strategy)

      local reset_license_data

      lazy_setup(function()
        reset_license_data = clear_license_env()
      end)

      lazy_teardown(function()
        assert(db:truncate())
        reset_license_data()
      end)

      describe("CORS", function()

        lazy_setup(function()
          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_is_legacy = true,
          })
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("single portal_cors_origins", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              enforce_rbac = rbac,
              license_path = "spec-ee/fixtures/mock_license.json",
              portal_cors_origins = "http://foo.example"
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

          it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

            local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals("http://foo.example", origin)
          end)
        end)

        describe("multiple portal_cors_origins", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              enforce_rbac = rbac,
              license_path = "spec-ee/fixtures/mock_license.json",
              portal_cors_origins = "http://foo.example, http://bar.example"
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

          it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
              headers = {
                ['Origin'] = "http://bar.example",
              },
            })

            local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals("http://bar.example", origin)
          end)
        end)

         describe("portal_cors_origins *", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              license_path = "spec-ee/fixtures/mock_license.json",
              enforce_rbac = rbac,
              portal_cors_origins = "*"
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

           it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

             local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals("*", origin)
          end)
        end)

         describe("portal_cors_origins nil, portal_gui_protocol and portal_gui_host default", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              license_path = "spec-ee/fixtures/mock_license.json",
              enforce_rbac = rbac,
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

           it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

             local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals(helpers.test_conf.portal_gui_protocol .. "://" .. helpers.test_conf.portal_gui_host, origin)
          end)
        end)

         describe("portal_cors_origins nil, portal_gui_protocol and portal_gui_host set", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              enforce_rbac = rbac,
              license_path = "spec-ee/fixtures/mock_license.json",
              portal_gui_protocol = "http",
              portal_gui_host = "example.foo"
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

           it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

             local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals("http://example.foo", origin)
          end)
        end)

         describe("portal_cors_origins nil, portal_gui_protocol and portal_gui_host set, portal_gui_use_subdomains true", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              enforce_rbac = rbac,
              license_path = "spec-ee/fixtures/mock_license.json",
              portal_gui_protocol = "http",
              portal_gui_host = "example.foo",
              portal_gui_use_subdomains = true,
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

           it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

             local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals("http://default.example.foo", origin)
          end)
        end)

         describe("portal_cors_origins nil, portal_gui_protocol and portal_gui_host default, portal_gui_use_subdomains true", function()
          lazy_setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              license_path = "spec-ee/fixtures/mock_license.json",
              enforce_rbac = rbac,
              portal_gui_use_subdomains = true,
            }))
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

           it("sets the correct Access-Control-Allow-Origin header", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

             local origin = assert.response(res).has.header("Access-Control-Allow-Origin")
            assert.equals(helpers.test_conf.portal_gui_protocol .. "://default." .. helpers.test_conf.portal_gui_host, origin)
          end)
        end)
      end)

      describe("/files without auth", function()
        lazy_setup(function()
          db:truncate()
          configure_portal(db, {
            portal = true,
            portal_is_legacy = true,
          })

          assert(helpers.start_kong({
            database   = strategy,
            portal     = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            enforce_rbac = rbac,
          }))

          insert_files(db)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          it("retrieves files", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(20, #json.data)
          end)

          it("retrieves only unauthenticated files", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files/unauthenticated",
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(10, #json.data)
            for key, value in ipairs(json.data) do
              assert.equal(false, value.auth)
            end
          end)

          it("retrieves filtered unauthenticated files", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files/unauthenticated?type=partial",
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(5, #json.data)
            for key, value in ipairs(json.data) do
              assert.equal(false, value.auth)
            end
          end)

          it("can paginate unauthenticated files", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files/unauthenticated?type=partial&size=4",
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(4, #json.data)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = json.next
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(1, #json.data)
            assert.equal(ngx.null, json.next)
          end)
        end)
      end)

      describe("/register", function()
        describe("basic-auth", function()
          local password = "tHiSPasSw0rDiSTr*ng"

          lazy_setup(function()
            assert(db:truncate())

            assert(helpers.start_kong({
              database = strategy,
              portal = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              license_path = "spec-ee/fixtures/mock_license.json",
              portal_auth = "basic-auth",
              enforce_rbac = rbac,
              portal_session_conf = PORTAL_SESSION_CONF,
              portal_auth_password_complexity = [[{"kong-preset": "min_8"}]],
              admin_gui_url = "http://localhost:8080",
            }))

            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_is_legacy = true,
            })
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
          end)

          after_each(function()
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns a 400 if password is missing", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local password = resp_body_json.fields.password
              assert.equal("password is required", password)
            end)

            it("returns a 400 if password is too short", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local password = resp_body_json.fields.password

              assert.equal("Invalid password: too short", password)
            end)

            it("returns a 400 if password is too weak", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                password = "asdfasdfasdfasdf",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local password = resp_body_json.fields.password

              assert.equal("Invalid password: not enough different characters or classes", password)
            end)

            it("returns a 400 if email is invalid format", function()
              local res = register_developer(portal_api_client, {
                email = "grucekonghq.com",
                password = password,
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("invalid email address grucekonghq.com", message)
            end)

            it("returns a 400 if email is invalid type", function()
              local res = register_developer(portal_api_client, {
                email = 9000,
                password = password,
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("expected a string", message)
            end)

            it("returns a 400 if email is missing", function()
              local res = register_developer(portal_api_client, {
                password = password,
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("required field missing", message)
            end)

            it("returns a 400 if meta is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                password = password,
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.meta
              assert.equal("required field missing", message["full_name"])
            end)

            it("returns a 400 if meta is invalid", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                password = password,
                meta = "{weird}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.meta

              assert.equal("required field missing", message["full_name"])
            end)

            it("returns a 400 if status is included in the request", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                password = password,
                meta = "{\"full_name\":\"I Like Turtles\"}",
                status = enums.CONSUMERS.STATUS.APPROVED,
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.status

              assert.equal("invalid field", message)
            end)

            it("registers a developer and set status to pending", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                password = password,
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local developer = resp_body_json.developer

              assert.is_true(utils.is_valid_uuid(developer.id))
              assert.is_true(utils.is_valid_uuid(developer.consumer.id))
              assert.equal(enums.CONSUMERS.STATUS.PENDING, developer.status)
              assert.equal("noob@konghq.com", developer.email)
              assert.equal("{\"full_name\":\"I Like Turtles\"}", developer.meta)
              assert.is_nil(resp_body_json.email)
            end)

            describe("no meta fields", function()
              lazy_setup(function()
                ee_helpers.register_rbac_resources(db)
                local opt = {
                  override_default_headers = {
                    ["Kong-Admin-Token"] = "letmein-default",
                    ["Content-Type"] = "application/json",
                  }
                }

                helpers.wait_for_all_config_update(opt)

                admin_client_request({
                  method = "PATCH",
                  path = "/workspaces/default",
                  body = {
                    config = {
                      portal = true,
                      portal_auth = "basic-auth",
                      portal_developer_meta_fields = "[]",
                    }
                  },
                  headers = {
                    ["Kong-Admin-Token"] = "letmein-default",
                    ["Content-Type"] = "application/json",
                  }
                })

                helpers.wait_for_all_config_update(opt)
              end)

              it("can register a developer with no meta fields", function()
                local res = register_developer(portal_api_client, {
                  email = "noobz@konghq.com",
                  password = password,
                })

                assert.res_status(200, res)
              end)
            end)
          end)
        end)

        describe("key-auth", function()
          lazy_setup(function()
            assert(db:truncate())

            assert(helpers.start_kong({
              database = strategy,
              portal = "on",
              portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
              portal_auth = "key-auth",
              license_path = "spec-ee/fixtures/mock_license.json",
              enforce_rbac = rbac,
              portal_session_conf = PORTAL_SESSION_CONF,
              admin_gui_url = "http://localhost:8080",
            }))

            configure_portal(db, {
              portal = true,
              portal_auth = "key-auth",
            })
          end)

          lazy_teardown(function()
            helpers.stop_kong()
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
          end)

          after_each(function()
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns a 400 if key is missing", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local key = resp_body_json.fields.key

              assert.equal("key is required", key)
            end)

            it("returns a 400 if email is invalid format", function()
              local res = register_developer(portal_api_client, {
                email = "grucekonghq.com",
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("invalid email address grucekonghq.com", message)
            end)

            it("returns a 400 if email is invalid type", function()
              local res = register_developer(portal_api_client, {
                email = 9000,
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("expected a string", message)
            end)

            it("returns a 400 if email is missing", function()
              local res = register_developer(portal_api_client, {
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("required field missing", message)
            end)

            it("returns a 400 if meta is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.meta

              assert.equal("required field missing", message["full_name"])
            end)

            it("returns a 400 if meta is invalid", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
                meta = "{weird}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.meta

              assert.equal("required field missing", message["full_name"])
            end)

            it("returns a 400 if meta.full_name key is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
                meta = "{\"something_else\":\"not full name\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local full_name = resp_body_json.fields.meta.full_name
              local something_else = resp_body_json.fields.meta.something_else

              assert.equal("required field missing", full_name)
              assert.equal("unknown field", something_else)
            end)

            it("returns a 400 if status is included in the request", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                key = "iheartkong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
                status = enums.CONSUMERS.STATUS.APPROVED,
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.status

              assert.equal("invalid field", message)
            end)

            it("returns a 400 if key is already in use", function()
              local res = register_developer(portal_api_client, {
                email = "dev1@konghq.com",
                key = "taken",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              assert.res_status(200, res)

              local res = register_developer(portal_api_client, {
                email = "dev2@konghq.com",
                key = "taken",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)

              local resp_body_json = cjson.decode(body)
              local key = resp_body_json.fields.key

              assert.equal("invalid api key", key)
            end)

            it("registers a developer and set status to pending", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                key = "iheartkong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local developer = resp_body_json.developer

              assert.is_true(utils.is_valid_uuid(developer.id))
              assert.is_true(utils.is_valid_uuid(developer.consumer.id))
              assert.equal(enums.CONSUMERS.STATUS.PENDING, developer.status)
              assert.equal("noob@konghq.com", developer.email)
              assert.equal("{\"full_name\":\"I Like Turtles\"}", developer.meta)
              assert.is_nil(resp_body_json.email)
            end)
          end)
        end)
      end)

      describe("Authenticated Routes [basic-auth]", function()
        local default_developer, approved_developer, locked_out_developer

        lazy_setup(function()
          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            portal_is_legacy = true,
            admin_gui_url = "http://localhost:8080",
            portal_auth_login_attempts = 3,
            portal_auth_password_complexity = [[{"kong-preset": "min_8"}]],
          }))

          ee_helpers.register_rbac_resources(db)
          local opt = {
            override_default_headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          }

          helpers.wait_for_all_config_update(opt)

          admin_client_request({
            method = "PATCH",
            path = "/workspaces/default",
            body = {
              config = {
                portal = true,
                portal_auth = "basic-auth",
                portal_auto_approve = false,
              }
            },
            headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          })

          helpers.wait_for_all_config_update(opt)

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, {
            email = "pending@konghq.com",
            password = "Pending-Developer",
            meta = "{\"full_name\":\"Dr. Forgotten Developer\"}",
          })
          assert.res_status(200, res)

          -- enable auto approve
          admin_client_request({
            method = "PATCH",
            path = "/workspaces/default",
            body = {
              config = {
                portal = true,
                portal_auth = "basic-auth",
                portal_auto_approve = true,
              }
            },
            headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          })

          helpers.wait_for_all_config_update(opt)

          -- register default developer
          local res = register_developer(portal_api_client, "basic-auth")
          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          default_developer = resp_body_json.developer

          insert_files(db)

          local res = register_developer(portal_api_client, {
            email = "dale@konghq.com",
            password = "Kong-Strong",
            meta = "{\"full_name\":\"1337\"}",
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.developer

          helpers.wait_for_all_config_update(opt)

          local res = register_developer(portal_api_client, {
            email = "lockout@konghq.com",
            password = "locked-Developer",
            meta = "{\"full_name\":\"YEE\"}",
          })
          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          locked_out_developer = resp_body_json.developer

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          assert(helpers.stop_kong())
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/forgot-password [basic-auth]", function()
          describe("POST", function()
            it("should return 400 if called with invalid email", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "grucekonghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("invalid email address grucekonghq.com", message)
            end)

            it("should return 200 if called with email of a nonexistent user", function()

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "creeper@example.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local secrets = {}
              for row in db.consumer_reset_secrets:each(nil, { workspace = ngx.null }) do
                table.insert(secrets, row)
              end
              assert.equals(0, #secrets)
            end)

            it("should return 200 and generate a token secret if called with developer email", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              assert.is_string(rows[1].secret)
              assert.equal(1, #rows)
            end)

            it("should invalidate the previous secret if called twice", function()
              db:truncate("consumer_reset_secrets")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              assert.equal(1, #rows)
              assert.is_string(rows[1].secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local pending = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
                if secret.status == enums.TOKENS.STATUS.PENDING then
                  pending[#pending + 1] = secret
                end
              end

              assert.equal(1, #pending)

              db.consumer_reset_secrets:delete({ id = pending[1].id })

              local invalidated = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
                if secret.status == enums.TOKENS.STATUS.INVALIDATED then
                  invalidated[#invalidated + 1] = secret
                end
              end

              assert.equal(1, #invalidated)
              db.consumer_reset_secrets:delete({ id = invalidated[1].id })

              assert.not_equal(pending[1].secret, invalidated[1].secret)
            end)
          end)
        end)

        describe("/auth [basic-auth]", function()
          describe("GET", function()
            it("returns 401 when consumer is not approved", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("pending@konghq.com:Pending-Developer"),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals('Unauthorized: Developer status: PENDING', json.message)

              local cookie = assert.response(res).has.header("Set-Cookie")

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals('Unauthorized: Developer status: PENDING', json.message)
            end)

            it("returns 401 with invalid password ", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:weirdo"),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)
            end)

            it("account locks after portal_auth_login_attempts, resets on password reset", function()
              local cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:Kong-Strong"),
              }, true)

              -- login succeeds
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)

              -- 3 unsuccessful attempts
              for i = 1, 3 do
                local res = authenticate(portal_api_client, {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:wrong"),
                })

                local body = assert.res_status(401, res)
                local json = cjson.decode(body)
                assert.equals("Invalid authentication credentials", json.message)
              end

              -- valid password now fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:Kong-Strong"),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              -- reset password flow
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = default_developer.email,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local pending = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
                if secret.status == enums.TOKENS.STATUS.PENDING then
                  pending[#pending + 1] = secret
                end
              end

              local secret = pending[1].secret

              local claims = {id = default_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                  password = "Kong-Strong",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              -- new password auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:Kong-Strong"),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
            end)

            it("returns 401 with invalid username ", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("derp:kong"),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)
            end)

            it("returns 200 and session cookie with valid credentials", function()
              local cookie = authenticate(portal_api_client, "basic-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
            end)
          end)

          describe("DELETE", function()
            it("destroys the session if logout_query_arg (session_logout by default) is sent", function()
              local cookie = authenticate(portal_api_client, "basic-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/auth?session_logout=true",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
              cookie = assert.response(res).has.header("Set-Cookie")

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)

              assert.equals("Invalid authentication credentials", json.message)
            end)
          end)
        end)

        describe("/files [basic-auth]", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
                headers = {
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("retrieves files", function()
              local cookie = authenticate(portal_api_client, "basic-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.equal(20, #json.data)
            end)
          end)

          describe("POST, PATCH, PUT", function ()
            it("does not allow forbidden methods", function()
              local cookie = authenticate(portal_api_client, "basic-auth", true)
              local res_put = assert(portal_api_client:send {
                method = "PUT",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_put)

              local res_patch = assert(portal_api_client:send {
                method = "PATCH",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_patch)

              local res_post = assert(portal_api_client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_post)
            end)
          end)
        end)

        describe("/credentials/:plugin [basic-auth]", function()
          local credential
          local credential_key_auth
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            cookie = authenticate(portal_api_client, "basic-auth", true)
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns 404 if plugin is not one of the allowed auth plugins", function()
              local plugin = "awesome-custom-plugin"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  username = "dude",
                  password = "hunter1"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("creates a basic-auth credential", function()
              local plugin = "basic-auth"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  username = "dude",
                  password = "hunter1"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)

              credential = resp_body_json

              assert.equal("dude", credential.username)
              assert.are_not.equals("hunter1", credential.password)
              assert.is_true(utils.is_valid_uuid(credential.id))
            end)

            it("creates a key-auth credential", function()
              local plugin = "key-auth"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  key = "letmein"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)

              credential_key_auth = resp_body_json

              assert.equal("letmein", credential_key_auth.key)
              assert.is_true(utils.is_valid_uuid(credential_key_auth.id))
            end)
          end)

          describe("GET", function()
            lazy_setup(function()
              db:truncate("keyauth_credentials")
              db:truncate("basicauth_credentials")
            end)

            after_each(function()
              db:truncate("keyauth_credentials")
              db:truncate("basicauth_credentials")
            end)

            it("retrieves a basic-auth credential", function()
              local credential = assert(kong.db.daos["basicauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                username = "dude",
                password = "hunter1",
              }))

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth/" .. credential.id,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.same(credential, credential_res)
            end)

            it("retrieves a key-auth credential", function()
              local credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                key = "asdf",
              }))

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth/" .. credential.id,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.same(credential, credential_res)
            end)
          end)

          describe("PATCH", function()
            after_each(function()
              db:truncate("keyauth_credentials")
              db:truncate("basicauth_credentials")
            end)

            it("returns 404 if plugin is not one of the allowed auth plugins", function()
              local credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = approved_developer.consumer.id },
                key = "asdf",
              }))

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = "/credentials/awesome-custom-plugin/" .. credential.id,
                body = {
                  id = credential.id,
                  username = "dudett",
                  password = "a-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("updates a basic-auth credential", function()
              local credential = assert(kong.db.daos["basicauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                username = "dude",
                password = "hunter1",
              }))

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = "/credentials/basic-auth/" .. credential.id,
                body = {
                  id = credential.id,
                  username = "dudett",
                  password = "a-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("dudett", credential_res.username)
              assert.are_not.equals("a-new-password", credential_res.password)
              assert.is_true(utils.is_valid_uuid(credential_res.id))

              assert.are_not.equals(credential_res.username, credential.username)
            end)

            it("updates a key-auth credential", function()
              local credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                key = "asdf",
              }))

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = "/credentials/key-auth/" .. credential.id,
                body = {
                  id = credential.id,
                  key = "a-new-key"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("a-new-key", credential_res.key)
              assert.is_true(utils.is_valid_uuid(credential_res.id))
            end)

            it("updates a basic-auth credential by id", function()
              local credential = assert(kong.db.daos["basicauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                username = "dude",
                password = "hunter1",
              }))

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path =  "/credentials/basic-auth/" .. credential.id,
                body = {
                  username = "duderino",
                  password = "a-new-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("duderino", credential_res.username)
              assert.are_not.equals("a-new-new-password", credential_res.password)
              assert.is_true(utils.is_valid_uuid(credential_res.id))

              assert.are_not.equals(credential_res.username, credential.username)
            end)

            it("updates a key-auth credential by id", function()
              local credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                key = "asdf",
              }))

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = "/credentials/key-auth/" .. credential.id,
                body = {
                  key = "duderino",
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("duderino", credential_res.key)
              assert.is_true(utils.is_valid_uuid(credential_res.id))
            end)

            it("does not allow patch with body-path mismatched id", function()
              local res = register_developer(portal_api_client, {
                  email = "attackerdev@konghq.com",
                  password = "s<r1P7-k1Ddi3++",
                  meta = "{\"full_name\":\"Kong Dev\"}",
                })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local attacker_dev = resp_body_json.developer

              local attacker_credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = attacker_dev.consumer.id },
                key = "Attacker_key",
              }))

              local victm_credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = approved_developer.consumer.id },
                key = "Victmkey1",
              }))


              res = assert(portal_api_client:send {
                method = "PATCH",
                path = "/credentials/key-auth/" .. attacker_credential.id,
                body = {
                  id = victm_credential.id,
                  key = "new_key",
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(400, res)
            end)
          end)

          describe("DELETE", function()
            it("deletes a basic-auth credential", function()
              local credential = assert(kong.db.daos["basicauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                username = "dude",
                password = "Tfgsd223P!_",
              }))

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/credentials/basic-auth/" .. credential.id,
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth/" .. credential.id,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("deletes a key-auth credential", function()
              local credential = assert(kong.db.daos["keyauth_credentials"]:insert({
                consumer = { id = default_developer.consumer.id },
                key = "asdf",
              }))

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/credentials/key-auth/" .. credential.id,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth/" .. credential.id,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)

          describe("GET page", function()
            lazy_setup(function()
              portal_api_client = assert(ee_helpers.portal_api_client())

              local function make_username(i)
                if i % 2 == 0 then
                  return 'guy' .. i
                end
                return 'dude' .. i
              end

              for i = 1, 10 do
                local res = assert(portal_api_client:send {
                  method = "POST",
                  path = "/credentials/basic-auth",
                  body = {
                    username = make_username(i),
                    password = "hunter1"
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    ["Cookie"] = cookie,
                  },
                })

                assert.res_status(201, res)
              end

              local function make_key(i)
                if i % 2 == 0 then
                  return 'kwikset' .. i
                end
                return 'schlage' .. i
              end

              for i = 1, 10 do
                local res = assert(portal_api_client:send {
                  method = "POST",
                  path = "/credentials/key-auth",
                  body = {
                    key = make_key(i)
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    ["Cookie"] = cookie,
                  },
                })

                assert.res_status(201, res)
              end
            end)

            it("filters basic-auth creds by username from query params", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth?username=guy&sort_by=username",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("guy10", credential_res.data[1].username)
              assert.equal("guy2", credential_res.data[2].username)
              assert.equal("guy4", credential_res.data[3].username)
              assert.equal("guy6", credential_res.data[4].username)
              assert.equal("guy8", credential_res.data[5].username)

              res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth?username=dude&sort_by=username",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              body = assert.res_status(200, res)
              credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("dude1", credential_res.data[1].username)
              assert.equal("dude3", credential_res.data[2].username)
              assert.equal("dude5", credential_res.data[3].username)
              assert.equal("dude7", credential_res.data[4].username)
              assert.equal("dude9", credential_res.data[5].username)
            end)

            it("filters key-auth creds by key from query params", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth?key=wiks&sort_by=key",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("kwikset10", credential_res.data[1].key)
              assert.equal("kwikset2", credential_res.data[2].key)
              assert.equal("kwikset4", credential_res.data[3].key)
              assert.equal("kwikset6", credential_res.data[4].key)
              assert.equal("kwikset8", credential_res.data[5].key)

              res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth?key=schla&sort_by=key",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              body = assert.res_status(200, res)
              credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("schlage1", credential_res.data[1].key)
              assert.equal("schlage3", credential_res.data[2].key)
              assert.equal("schlage5", credential_res.data[3].key)
              assert.equal("schlage7", credential_res.data[4].key)
              assert.equal("schlage9", credential_res.data[5].key)
            end)
          end)
        end)

        describe("/config [basic-auth]", function()
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            cookie = authenticate(portal_api_client, "basic-auth", true)
            close_clients(portal_api_client)
          end)

          describe("GET", function()
            it("retrieves the kong config tailored for the dev portal", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/config",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              local config = resp_body_json

              assert.same({}, config.plugins.enabled_in_cluster)
            end)
          end)
        end)

        describe("/validate-reset [basic-auth]", function()
          local secret

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = "gruce@konghq.com",
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local pending = {}
            for secret in db.consumer_reset_secrets:each_for_consumer({ id = default_developer.consumer.id}) do
              if secret.status == enums.TOKENS.STATUS.PENDING then
                pending[#pending + 1] = secret
              end
            end

            secret = pending[1].secret
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("should return 400 if called without a token", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = "",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("token is required", message)
            end)

            it("should return 401 if called with an invalid jwt format", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = "im_a_token_lol",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = bad_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is expired", function()
              local claims = {id = approved_developer.consumer.id, exp = time() - 100000}
              local expired_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = expired_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token contains non-existent developer", function()
              local claims = {id = uuid(), exp = time() + 100000}
              local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = random_uuid_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 200 if called with a valid token", function()
              local claims = {id = default_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = valid_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)
            end)
          end)
        end)

        describe("/developer [basic-auth]", function()
          local developer
          local cookie

          lazy_setup(function()
            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_auto_approve = true,
            })

            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "devdevdev@konghq.com",
              password = "Developing-is-Cool!",
              meta = "{\"full_name\":\"Kong Dev\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("devdevdev@konghq.com:Developing-is-Cool!"),
            }, true)

            close_clients(portal_api_client)
          end)

          describe("GET", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("returns the authenticated developer", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              assert.same(developer, resp_body_json)
            end)
          end)

          describe("DELETE", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
                headers = {
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("deletes authenticated developer", function()
              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(401, res)
            end)
          end)
        end)

        describe("/developer/meta [basic-auth]", function()
          local cookie

          lazy_setup(function()
            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_auto_approve = true,
            })

            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "metachange@konghq.com",
              password = "Bloodsport-1988",
              meta = "{\"full_name\":\"I will change\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("metachange@konghq.com:Bloodsport-1988"),
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)
            close_clients(portal_api_client)
          end)

          describe("PUT", function()
            it("updates the meta", function()
              local new_meta = "{\"full_name\":\"KONG!!!\"}"

              local res = assert(portal_api_client:send {
                method = "PUT",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(200, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local meta = resp_body_json.meta

              assert.equal(meta, new_meta)
            end)

            it("keys not matching schema throw an error", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local current_meta = resp_body_json.meta

              local new_meta = "{\"new_key\":\"not in current schema\"}"

              local res = assert(portal_api_client:send {
                method = "PUT",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(400, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local new_meta = resp_body_json.meta

              assert.equal(new_meta, current_meta)
            end)
          end)
        end)

        describe("/developer/meta-fields", function()
          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            close_clients(portal_api_client)
          end)

          describe("GET", function()
            it("returns default developer meta fields in format for portal templates", function ()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer/meta_fields",
                headers = {
                  ["Content-Type"] = "application/json",
                },
              })
              local body = assert.res_status(200, res)
              local expect = {{
                title = "full_name",
                label = "Full Name",
                is_email = false,
                validator = {
                   type = "string",
                   required = true,
                  }
                },
              }

              assert(expect, body)
            end)
          end)
        end)

        describe("/reset-password [basic-auth]", function()
          local secret
          local approved_developer
          local password = "tHiSPasSw0rDiSTr*ng"

          lazy_setup(function()

            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_auto_approve = true,
            })

            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "kongkong@konghq.com",
              password = password,
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            approved_developer = resp_body_json.developer

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = approved_developer.email,
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local pending = {}
            for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
              if secret.status == enums.TOKENS.STATUS.PENDING then
                pending[#pending + 1] = secret
              end
            end

            secret = pending[1].secret
            close_clients(portal_api_client)
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
          end)

          after_each(function()
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("should return 400 if called without a token", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = "",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("token is required", message)
            end)

            it("should return 401 if called with an invalid jwt format", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = "im_a_token_lol",
                  password = password,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = bad_jwt,
                  password = password,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is expired", function()
              local claims = {id = approved_developer.consumer.id, exp = time() - 100000}
              local expired_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = expired_jwt,
                  password = password,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token contains non-existent developer", function()
              local claims = {id = uuid(), exp = time() + 100000}
              local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = random_uuid_jwt,
                  password = password,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 400 if called without a password", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("password is required", message)
            end)

            it("should return 400 if called with a password too short", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                  password = "asdf"
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.password

              assert.equal("Invalid password: too short", message)
            end)

            it("should return 400 if called with a password too simple", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                  password = "askdfjlsakjdflksajfl"
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.password

              assert.equal("Invalid password: not enough different characters or classes", message)
            end)

            it("should return 200 if called with a valid token, ignoring email_or_id param (regression)", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  email_or_id = "this_will_be_ignored",
                  token = valid_jwt,
                  password = password .. "1",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              -- token is consumed
              assert.equal(1, #rows)
              assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

              -- old password fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("kongkong@konghq.com:" .. password),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              -- new password auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("kongkong@konghq.com:" .. password .. "1"),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
            end)
          end)
        end)

        describe("/developer/email [basic-auth]", function()
          local other_developer
          local cookie

          lazy_setup(function()

            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_auto_approve = true,
            })

            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "changeme@konghq.com",
              password = "I-like-pancakes",
              meta = "{\"full_name\":\"Bowser\"}",
            })

            assert.res_status(200, res)

            res = register_developer(portal_api_client, {
              email = "otherdeveloper@konghq.com",
              password = "pancakesareRAD!",
              meta = "{\"full_name\":\"Toad\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            other_developer = resp_body_json.developer

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("changeme@konghq.com:I-like-pancakes"),
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:I-like-pancakes"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("otherdeveloper@konghq.com:pancakesareRAD!"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)
            close_clients(portal_api_client)
          end)

          describe("PATCH", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "email@lol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "email@lol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = "nope",
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)
            end)


            it("returns 400 if patched with an invalid email", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "emailol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("missing '@' symbol", message)
            end)

            it("returns 409 if patched with an email that already exists", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = other_developer.email,
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(409, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("already exists with value '" .. other_developer.email .. "'", message)
            end)

            it("updates both email and username", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "new_email@whodis.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(200, res)

              -- old email fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("changeme@konghq.com:I-like-pancakes"),
              })

              assert.res_status(401, res)
              cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              -- new email auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:I-like-pancakes"),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              assert.equal("new_email@whodis.com", resp_body_json.email)
            end)
          end)
        end)

        describe("/developer/password [basic-auth]", function()
          local cookie
          local changeme_password = "cHaNgEm3Ple@s3"
          local password = "tHiSPasSw0rDiSTr*ng"

          lazy_setup(function()
            assert(db:truncate())

            configure_portal(db, {
              portal = true,
              portal_auth = "basic-auth",
              portal_auto_approve = true,
            })

            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "passwordchange@konghq.com",
              password = changeme_password,
              meta = "{\"full_name\":\"Mario\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:" .. changeme_password),
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:" .. password),
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)
            close_clients(portal_api_client)
          end)

          describe("PATCH", function()
            it("returns 401 if not authenticated", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "hunter1",
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "hunter1",
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = "nope",
                }
              })

              assert.res_status(401, res)
            end)

            it("returns 400 if patched with no password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {},
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("key or password is required", message)
            end)

            it("returns 400 if patched with too short password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "asdf",
                  old_password = changeme_password
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.password

              assert.equal("Invalid password: too short", message)
            end)

            it("returns 400 if patched with too simple password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "asdfasdfasdfasdf",
                  old_password = changeme_password
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.password

              assert.equal("Invalid password: not enough different characters or classes", message)
            end)

            it("returns 400 if patched with no old password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "wontwork"
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Must include old_password", message)
            end)

            it("returns 400 if patched with wrong old password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "wontwork",
                  old_password = "alsowontwork"
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Old password is invalid", message)
            end)

            it("updates the password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = password,
                  old_password = changeme_password
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(204, res)

              -- old password fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:" .. changeme_password)
              })

              cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)
              assert.res_status(401, res)

              -- new password auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:" .. password),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(200, res)
            end)
          end)
        end)
      end)

      describe("Authenticated Routes [key-auth]", function()
        local approved_developer

        lazy_setup(function()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            portal_auth = "key-auth",
            portal_is_legacy = true,
            enforce_rbac = rbac,
            portal_auto_approve = "off",
            admin_gui_url = "http://localhost:8080",
          }))

          ee_helpers.register_rbac_resources(db)
          local opt = {
            override_default_headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          }

          helpers.wait_for_all_config_update(opt)
          admin_client_request({
            method = "PATCH",
            path = "/workspaces/default",
            body = {
              config = {
                portal = true,
                portal_auth = "key-auth",
                portal_auto_approve = false,
              }
            },
            headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          })

          helpers.wait_for_all_config_update(opt)

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, {
            email = "dale@konghq.com",
            key = "kong",
            meta = "{\"full_name\":\"1337\"}",
          })

          assert.res_status(200, res)

          admin_client_request({
            method = "PATCH",
            path = "/workspaces/default",
            body = {
              config = {
                portal = true,
                portal_auth = "key-auth",
                portal_auto_approve = true,
              }
            },
            headers = {
              ["Kong-Admin-Token"] = "letmein-default",
              ["Content-Type"] = "application/json",
            }
          })

          helpers.wait_for_all_config_update(opt)

          local res = register_developer(portal_api_client, "key-auth")
          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.developer

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/auth [key-auth]", function()
          describe("GET", function()
            it("returns 401 when consumer is not approved", function()
              local res = authenticate(portal_api_client, {
                ["apikey"] = "kong",
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same('Unauthorized: Developer status: PENDING', json.message)

              local cookie = assert.response(res).has.header("Set-Cookie")

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals('Unauthorized: Developer status: PENDING', json.message)
            end)

            it("returns 401 with invalid apikey ", function()
              local res = authenticate(portal_api_client, {
                ["apikey"] = "nope",
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)
            end)

            it("returns 200 and session cookie with valid apikey", function()
              local cookie = authenticate(portal_api_client, "key-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
            end)
          end)

          describe("DELETE", function()
            it("destroys the session if logout_query_arg (session_logout by default) is sent", function()
              local cookie = authenticate(portal_api_client, "key-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/auth?session_logout=true",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
              cookie = assert.response(res).has.header("Set-Cookie")

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)

              assert.equals("Invalid authentication credentials", json.message)
            end)
          end)
        end)

        describe("/files [key-auth]", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("retrieves files", function()
              local cookie = authenticate(portal_api_client, "key-auth", true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.equal(20, #json.data)
            end)
          end)

          describe("POST, PATCH, PUT", function ()
            it("does not allow forbidden methods", function()
              local cookie = authenticate(portal_api_client, "key-auth", true)
              local res_put = assert(portal_api_client:send {
                method = "PUT",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_put)

              local res_patch = assert(portal_api_client:send {
                method = "PATCH",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_patch)

              local res_post = assert(portal_api_client:send {
                method = "POST",
                path = "/files",
                body = {
                  name = "test",
                  contents = "hello world",
                  type = "dog"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_post)
            end)
          end)
        end)

        describe("/forgot-password [key-auth]", function()
          describe("POST", function()
            it("should return 400 if called with invalid email", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "grucekonghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("invalid email address grucekonghq.com", message)
            end)

            it("should return 200 if called with email of a nonexistent user", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "creeper@example.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              assert.equals(0, #rows)
            end)

            it("should return 200 and generate a token secret if called with developer email", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              assert.is_string(rows[1].secret)
              assert.equal(1, #rows)
            end)

            it("should invalidate the previous secret if called twice", function()
              db:truncate("consumer_reset_secrets")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              assert.equal(1, #rows)
              assert.is_string(rows[1].secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/forgot-password",
                body = {
                  email = "gruce@konghq.com",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local pending = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                if secret.status == enums.TOKENS.STATUS.PENDING then
                  pending[#pending + 1] = secret
                end
              end

              assert.equal(1, #pending)
              db.consumer_reset_secrets:delete({ id = pending[1].id })

              local invalidated = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                if secret.status == enums.TOKENS.STATUS.INVALIDATED then
                  invalidated[#invalidated + 1] = secret
                end
              end

              assert.equal(1, #invalidated)
              db.consumer_reset_secrets:delete({ id = invalidated[1].id })

              assert.not_equal(pending[1].secret, invalidated[1].secret)
            end)
          end)
        end)

        describe("/reset-password [key-auth]", function()
          local secret
          local approved_developer

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "kongkong@konghq.com",
              key = "wowza",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            approved_developer = resp_body_json.developer

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = approved_developer.email,
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local pending = {}
            for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
              if secret.status == enums.TOKENS.STATUS.PENDING then
                pending[#pending + 1] = secret
              end
            end

            secret = pending[1].secret
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("should return 400 if called without a token", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = "",
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("token is required", message)
            end)

            it("should return 401 if called with an invalid jwt format", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = "im_a_token_lol",
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = bad_jwt,
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is expired", function()
              local claims = {id = approved_developer.consumer.id, exp = time() - 100000}
              local expired_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = expired_jwt,
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token contains non-existent developer", function()
              local claims = {id = uuid(), exp = time() + 100000}
              local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = random_uuid_jwt,
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 400 if called without a key", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                  key = "",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("key is required", message)
            end)

            it("should return 200 if called with a valid token, ignoring email_or_id param (regression)", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  email_or_id = "this_will_be_ignored",
                  token = valid_jwt,
                  key = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = {}
              for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
                rows[#rows + 1] = secret
              end

              -- token is consumed
              assert.equal(1, #rows)
              assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

              -- old key fails
              local res = authenticate(portal_api_client, {
                ["apikey"] = "wowza",
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              -- new key auths
              cookie = authenticate(portal_api_client, {
                ["apikey"] = "derp",
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(200, res)
            end)
          end)
        end)

        describe("/validate-reset [key-auth]", function()
          local secret

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = "gruce@konghq.com",
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local pending = {}
            for secret in db.consumer_reset_secrets:each_for_consumer({ id = approved_developer.consumer.id}) do
              if secret.status == enums.TOKENS.STATUS.PENDING then
                pending[#pending + 1] = secret
              end
            end

            secret = pending[1].secret
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("should return 400 if called without a token", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = "",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("token is required", message)
            end)

            it("should return 401 if called with an invalid jwt format", function()
              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = "im_a_token_lol",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = bad_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is expired", function()
              local claims = {id = approved_developer.consumer.id, exp = time() - 100000}
              local expired_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = expired_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token contains non-existent developer", function()
              local claims = {id = uuid(), exp = time() + 100000}
              local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = random_uuid_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 200 if called with a valid token", function()
              local claims = {id = approved_developer.consumer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/validate-reset",
                body = {
                  token = valid_jwt,
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)
            end)
          end)
        end)

        describe("/developer [key-auth]", function()
          local developer
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "devdevdev@konghq.com",
              key = "developer",
              meta = "{\"full_name\":\"Kong Dev\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "developer",
            }, true)

            close_clients(portal_api_client)
          end)

          describe("GET", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("returns the authenticated developer", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              assert.same(developer, resp_body_json)
            end)
          end)

          describe("DELETE", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
                headers = {
                  ["Cookie"] = "nope"
                },
              })

              assert.res_status(401, res)
            end)

            it("deletes authenticated developer", function()
              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(401, res)
            end)
          end)
        end)

        describe("/developer/password [key-auth]", function()
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "passwordchange@konghq.com",
              key = "changeme",
              meta = "{\"full_name\":\"Mario\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "changeme",
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local cookie = authenticate(portal_api_client, {
              ["apikey"] = "hunter1",
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)
            close_clients(portal_api_client)
          end)

          describe("PATCH", function()
            it("returns 401 if not authenticated", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  key = "hunter1",
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  key = "hunter1",
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = "nope",
                }
              })

              assert.res_status(401, res)
            end)

            it("returns 400 if patched with no key", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {},
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["apikey"] = "changeme",
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("key or password is required", message)
            end)

            it("updates the key", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  key = "hunter1",
                },
                path = "/developer/password",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["apikey"] = "changeme",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(204, res)

              -- old key fails
              local res = authenticate(portal_api_client, {
                ["apikey"] = "changeme",
              })

              cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)
              assert.res_status(401, res)

              -- new key auths
              cookie = authenticate(portal_api_client, {
                ["apikey"] = "hunter1",
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(200, res)
            end)
          end)
        end)

        describe("/developer/email [key-auth]", function()
          local other_developer
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "changeme@konghq.com",
              key = "pancakes",
              meta = "{\"full_name\":\"Bowser\"}",
            })

            assert.res_status(200, res)

            local res = register_developer(portal_api_client, {
              email = "otherdeveloper@konghq.com",
              key = "rad",
              meta = "{\"full_name\":\"Toad\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            other_developer = resp_body_json.developer

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "pancakes",
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "pancakes",
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "rad",
            }, true)

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)

            close_clients(portal_api_client)
          end)

          describe("PATCH", function()
            it("returns 401 if unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "email@lol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "email@lol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = "nope",
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(401, res)
            end)


            it("returns 400 if patched with an invalid email", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "emailol.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("missing '@' symbol", message)
            end)

            it("returns 409 if patched with an email that already exists", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = other_developer.email,
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(409, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.fields.email

              assert.equal("already exists with value '" .. other_developer.email .. "'", message)
            end)

            it("updates both email and username", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  email = "new_email@whodis.com",
                },
                path = "/developer/email",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              assert.res_status(200, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                  ["Content-Type"] = "application/json",
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              assert.equal("new_email@whodis.com", resp_body_json.email)
            end)
          end)
        end)

        describe("/developer/meta [key-auth]", function()
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "metachange@konghq.com",
              key = "Bloodsport-1988",
              meta = "{\"full_name\":\"I will change\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "Bloodsport-1988",
            }, true)

            close_clients(portal_api_client)
          end)

          lazy_teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)
            close_clients(portal_api_client)
          end)

          describe("PUT", function()
            it("updates the meta", function()
              local new_meta = "{\"full_name\":\"KONG!!!\"}"

              local res = assert(portal_api_client:send {
                method = "PUT",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(200, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local meta = resp_body_json.meta

              assert.equal(meta, new_meta)
            end)

            it("returns 400 for keys that are not in the extra fields schema", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local current_meta = resp_body_json.meta

              local new_meta = "{\"new_key\":\"not in current meta\"}"

              local res = assert(portal_api_client:send {
                method = "PUT",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(400, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/developer",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local new_meta = resp_body_json.meta

              assert.equal(new_meta, current_meta)
            end)
          end)
        end)

        describe("/credentials/:plugin [key-auth]", function()
          local credential
          local credential_key_auth
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            cookie = authenticate(portal_api_client, "key-auth", true)
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns 404 if plugin is not one of the allowed auth plugins", function()
              local plugin = "awesome-custom-plugin"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  username = "dude",
                  password = "hunter1"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("creates a basic-auth credential", function()
              local plugin = "basic-auth"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  username = "dude",
                  password = "hunter1"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)

              credential = resp_body_json

              assert.equal("dude", credential.username)
              assert.are_not.equals("hunter1", credential.password)
              assert.is_true(utils.is_valid_uuid(credential.id))
            end)

            it("creates a key-auth credential", function()
              local plugin = "key-auth"

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/credentials/" .. plugin,
                body = {
                  key = "letmein"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)

              credential_key_auth = resp_body_json

              assert.equal("letmein", credential_key_auth.key)
              assert.is_true(utils.is_valid_uuid(credential_key_auth.id))
            end)
          end)

          describe("GET", function()
            it("returns 404 if plugin is not one of the allowed auth plugins", function()
              local plugin = "awesome-custom-plugin"
              local path = "/credentials/" .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "GET",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("retrieves a basic-auth credential", function()
              local plugin = "basic-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "GET",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.same(credential, credential_res)
            end)

            it("retrieves a key-auth credential", function()
              local plugin = "key-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential_key_auth.id

              local res = assert(portal_api_client:send {
                method = "GET",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.same(credential_key_auth, credential_res)
            end)
          end)

          describe("PATCH", function()
            it("returns 404 if plugin is not one of the allowed auth plugins", function()
              local plugin = "awesome-custom-plugin"
              local path = "/credentials/" .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = path,
                body = {
                  id = credential.id,
                  username = "dudett",
                  password = "a-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("updates a basic-auth credential", function()
              local plugin = "basic-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = path,
                body = {
                  id = credential.id,
                  username = "dudett",
                  password = "a-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("dudett", credential_res.username)
              assert.are_not.equals("a-new-password", credential_res.password)
              assert.is_true(utils.is_valid_uuid(credential_res.id))

              assert.are_not.equals(credential_res.username, credential.username)
            end)

            it("updates a key-auth credential", function()
              local plugin = "key-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential_key_auth.id

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = path,
                body = {
                  id = credential_key_auth.id,
                  key = "a-new-key"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("a-new-key", credential_res.key)
              assert.is_true(utils.is_valid_uuid(credential_res.id))
            end)

            it("updates a basic-auth credential by id", function()
              local plugin = "basic-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = path,
                body = {
                  username = "duderino",
                  password = "a-new-new-password"
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("duderino", credential_res.username)
              assert.are_not.equals("a-new-new-password", credential_res.password)
              assert.is_true(utils.is_valid_uuid(credential_res.id))

              assert.are_not.equals(credential_res.username, credential.username)
            end)

            it("updates a key-auth credential by id", function()
              local plugin = "key-auth"
              local path = "/credentials/" .. plugin .. "/" .. credential_key_auth.id

              local res = assert(portal_api_client:send {
                method = "PATCH",
                path = path,
                body = {
                  key = "duderino",
                },
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)
              local credential_res = resp_body_json

              assert.equal("duderino", credential_res.key)
              assert.is_true(utils.is_valid_uuid(credential_res.id))
            end)
          end)

          describe("DELETE", function()
            it("deletes a basic-auth credential", function()
              local plugin = "basic-auth"
              local path = "/credentials/"
                            .. plugin .. "/" .. credential.id

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)

            it("deletes a key-auth credential", function()
              local plugin = "key-auth"
              local path = "/credentials/"
                            .. plugin .. "/" .. credential_key_auth.id

              local res = assert(portal_api_client:send {
                method = "DELETE",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = path,
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)

          describe("GET page", function()
            lazy_setup(function()
              portal_api_client = assert(ee_helpers.portal_api_client())

              local function make_username(i)
                if i % 2 == 0 then
                  return 'guy' .. i
                end
                return 'dude' .. i
              end

              for i = 1, 10 do
                local res = assert(portal_api_client:send {
                  method = "POST",
                  path = "/credentials/basic-auth",
                  body = {
                    username = make_username(i),
                    password = "hunter1"
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    ["Cookie"] = cookie,
                  },
                })

                assert.res_status(201, res)
              end

              local function make_key(i)
                if i % 2 == 0 then
                  return 'kwikset' .. i
                end
                return 'schlage' .. i
              end

              for i = 1, 10 do
                local res = assert(portal_api_client:send {
                  method = "POST",
                  path = "/credentials/key-auth",
                  body = {
                    key = make_key(i)
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    ["Cookie"] = cookie,
                  },
                })

                assert.res_status(201, res)
              end
            end)

            it("filters basic-auth creds by username from query params", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth?username=guy&sort_by=username",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("guy10", credential_res.data[1].username)
              assert.equal("guy2", credential_res.data[2].username)
              assert.equal("guy4", credential_res.data[3].username)
              assert.equal("guy6", credential_res.data[4].username)
              assert.equal("guy8", credential_res.data[5].username)

              res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/basic-auth?username=dude&sort_by=username",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              body = assert.res_status(200, res)
              credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("dude1", credential_res.data[1].username)
              assert.equal("dude3", credential_res.data[2].username)
              assert.equal("dude5", credential_res.data[3].username)
              assert.equal("dude7", credential_res.data[4].username)
              assert.equal("dude9", credential_res.data[5].username)
            end)

            it("filters key-auth creds by key from query params", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth?key=wiks&sort_by=key",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("kwikset10", credential_res.data[1].key)
              assert.equal("kwikset2", credential_res.data[2].key)
              assert.equal("kwikset4", credential_res.data[3].key)
              assert.equal("kwikset6", credential_res.data[4].key)
              assert.equal("kwikset8", credential_res.data[5].key)

              res = assert(portal_api_client:send {
                method = "GET",
                path = "/credentials/key-auth?key=schla&sort_by=key",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              body = assert.res_status(200, res)
              credential_res = cjson.decode(body)

              assert.equal(5, credential_res.total)
              assert.equal("schlage1", credential_res.data[1].key)
              assert.equal("schlage3", credential_res.data[2].key)
              assert.equal("schlage5", credential_res.data[3].key)
              assert.equal("schlage7", credential_res.data[4].key)
              assert.equal("schlage9", credential_res.data[5].key)
            end)
          end)
        end)

        describe("/config [key-auth]", function()
          local cookie

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            cookie = authenticate(portal_api_client, "key-auth", true)
            close_clients(portal_api_client)
          end)

          describe("GET", function()
            it("retrieves the kong config tailored for the dev portal", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/config",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              local config = resp_body_json

              assert.same({}, config.plugins.enabled_in_cluster)
            end)
          end)
        end)
      end)

      describe("Vitals off ", function()
        local cookie

        lazy_setup(function()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            vitals  = "off",
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })
          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          assert.res_status(200, res)

          cookie = authenticate(portal_api_client, "basic-auth", true)

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/vitals/status_codes/by_consumer", function()
          describe("GET", function()

            it("returns 404 when vitals if off", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)
        end)

        describe("/vitals/status_codes/by_consumer_and_route", function()
          describe("GET", function()

            it("returns 404 when vitals if off", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)
        end)

        describe("/vitals/consumers/cluster", function()
          describe("GET", function()

            it("returns 404 when vitals if off", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)
        end)

        describe("/vitals/consumers/nodes", function()
          describe("GET", function()

            it("returns 404 when vitals if off", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/nodes",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(404, res)
            end)
          end)
        end)
      end)

      describe("Vitals on", function()
        local approved_developer
        local cookie

        lazy_setup(function()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            vitals  = "on",
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.developer

          cookie = authenticate(portal_api_client, "basic-auth", true)

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/vitals/status_codes/by_consumer", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
              })

              assert.res_status(401, res)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                headers = {
                  ["Cookie"] = "nope",
                }
              })

              assert.res_status(401, res)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)

              assert.same({
                message = "Invalid query params: interval must be 'days', 'minutes' or 'seconds'",
              }, json)
            end)

            it("returns seconds data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "seconds",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = approved_developer.consumer.id,
                  entity_type = "consumer",
                  interval    = "seconds",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_total" },
                  status_code_totals = {
                    ["total"] = 0
                  },
                },
                stats = {},
              }, json)
            end)

            it("returns minutes data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "minutes",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = approved_developer.consumer.id,
                  entity_type = "consumer",
                  interval    = "minutes",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_total" },
                  status_code_totals = {
                    ["total"] = 0
                  },
                },
                stats = {},
              }, json)
            end)
          end)
        end)

        describe("/vitals/status_codes/by_consumer_and_route", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
              })

              assert.res_status(401, res)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)

              assert.same({
                message = "Invalid query params: interval must be 'days', 'minutes' or 'seconds'",
              }, json)
            end)

            it("returns seconds data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "seconds",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = approved_developer.consumer.id,
                  entity_type = "consumer_route",
                  interval    = "seconds",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_route_total" },
                  status_code_totals = {
                    ["total"] = 0
                  },
                },
                stats = {},
              }, json)
            end)

            it("returns minutes data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "minutes",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = approved_developer.consumer.id,
                  entity_type = "consumer_route",
                  interval    = "minutes",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_route_total" },
                  status_code_totals = {
                    ["total"] = 0
                  },
                },
                stats = {},
              }, json)
            end)
          end)
        end)

        describe("/vitals/consumers/cluster", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
              })

              assert.res_status(401, res)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(400, res)
              local json = cjson.decode(body)

              assert.same({
                message = "Invalid query params: interval must be 'days', 'minutes' or 'seconds'",
              }, json)
            end)

            it("returns seconds data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                query = {
                  interval = "seconds",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  interval    = "seconds",
                  level       = "cluster",
                },
                stats = {},
              }, json)
            end)

            it("returns minutes data", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                query = {
                  interval = "minutes",
                },
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  interval    = "minutes",
                  level       = "cluster",
                },
                stats = {},
              }, json)

            end)
          end)
        end)
      end)

      describe("Session", function()
        local cookie

        lazy_setup(function()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            vitals  = "on",
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          assert.res_status(200, res)
          cookie = authenticate(portal_api_client, "basic-auth", true)

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/session", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/session",
              })

              assert.res_status(401, res)
            end)

            it("returns session when authenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/session",
                headers = {
                  ["Cookie"] = cookie,
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.is.truthy(json.session.idling_timeout)
              assert.is.truthy(json.session.rolling_timeout)
              assert.is.truthy(json.session.absolute_timeout)
              assert.is.truthy(json.session.stale_ttl)
              assert.is.truthy(json.session.expires_in)
              assert.is.truthy(json.session.expires)

              -- TODO: below should be removed, kept for backward compatibility:
              assert.is.truthy(json.session.cookie)
              assert.is.truthy(json.session.cookie.lifetime)
              assert.is.truthy(json.session.cookie.renew)
            end)
          end)
        end)
      end)

      describe("Default Route", function()
        lazy_setup(function()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal = "on",
            portal_and_vitals_key = "753252c37f163b4bb601f84f25f0ab7609878673019082d50776196b97536880",
            license_path = "spec-ee/fixtures/mock_license.json",
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal_auth_password_complexity = [[{"kong-preset": "min_8"}]],
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_is_legacy = false,
          })
        end)

        lazy_teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        it("returns 404 when passed an illegal redirect in path", function()
          local res = assert(portal_api_client:send {
            method = "GET",
            path = "//wwww.google.com/",
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(404, res)
        end)
      end)
    end)
  end
end
