-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson      = require "cjson"
local pl_stringx = require "pl.stringx"
local helpers    = require "spec.helpers"
local utils      = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"
local clear_license_env = require("spec-ee.helpers").clear_license_env
local get_portal_and_vitals_key = require("spec-ee.helpers").get_portal_and_vitals_key


local PORTAL_SESSION_CONF = "{ \"secret\": \"super-secret\", \"cookie_secure\": false }"
local DEFAULT_CONSUMER = {
  ["basic-auth"] = {
    headers = {
      ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
    },
    body = {
      email = "gruce@konghq.com",
      password = "kong",
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


local rbac_mode = {"off", "on"}

for _, strategy in helpers.each_strategy() do
  for idx, rbac in ipairs(rbac_mode) do
    describe("Developer Portal - Portal API #" .. strategy .. " (ENFORCE_RBAC = " .. rbac .. ")", function()
      local portal_api_client
      local admin_client
      local _, db, _ = helpers.get_db_utils(strategy)
      local reset_license_data

      lazy_setup(function()
        reset_license_data = clear_license_env()
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
        reset_license_data()
      end)

      describe("/applications", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            enforce_rbac = rbac,
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
            portal_auth_login_attempts = 3,
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local devs = { "dale", "bob" }

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res
            for _, dev in ipairs(devs) do
              res = register_developer(portal_api_client, {
                email = dev .. "@konghq.com",
                password = "kong",
                meta = "{\"full_name\":\"n00b\"}",
              })

              assert.res_status(200, res)

              local cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64(dev .. "@konghq.com:kong"),
              }, true)

              for i = 1, 10, 1 do
                res = assert(portal_api_client:send {
                  method = "POST",
                  path = "/applications",
                  body = {
                    name = dev .. "s_app_" .. i,
                    custom_id = dev .. "_doggo_" .. i,
                  },
                  headers = {
                    ["Content-Type"] = "application/json",
                    ["Cookie"] = cookie
                  }
                })

                assert.res_status(200, res)
              end
            end
          end)

          lazy_teardown(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('developers'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
          end)

          it("Retrieves Applications only belonging to each developer", function()
            for _, dev in ipairs(devs) do
              local cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64(dev .. "@konghq.com:kong"),
              }, true)

              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/applications",
                headers = {
                  ["Cookie"] = cookie
                }
              })

              local body = assert.res_status(200, res)
              local resp_body_json = cjson.decode(body)

              for i, row in ipairs(resp_body_json.data) do
                assert.equal(1, pl_stringx.lfind(row.name, dev))
              end

              assert.equal(10, resp_body_json.total)
            end
          end)

          it("paginates properly", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications?size=3",
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(3, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)
            assert.equal(ngx.null, resp_body_json.next)
          end)
        end)

        describe("POST", function()
          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("should return 200 when creating a valid application", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("myfirstapp", resp_body_json.name)
            assert.equal("doggo", resp_body_json.custom_id)
          end)

          it("should return 409 when creating application with the same name", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo_two",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myfirstapp'", resp_body_json.fields.name)
          end)

          it("should return 409 when creating application with the same custom_id", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp_two",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with custom_id: 'doggo'", resp_body_json.fields.custom_id)
          end)

          it("should return 409 when creating a pre-existing application with whitespace added to name", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp ",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myfirstapp'", resp_body_json.fields.name)
          end)

          it("should return 400 if does not contain proper params", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("required field missing", resp_body_json.fields.name)
          end)
        end)
      end)

      describe("/applications/:applications", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer gets 200 when requesting a valid application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id,
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("myfirstapp", resp_body_json.name)
            assert.equal("doggo", resp_body_json.custom_id)
          end)

          it("developer gets 400 when requesting a non-existent Application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. utils.uuid(),
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(404, res)
          end)
        end)

        describe("PATCH", function()
          local application, application_2, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myotherapp",
                custom_id = "doggo_2",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application_2 = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can update application", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = "mysecondapp",
                custom_id = "catto",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("mysecondapp", resp_body_json.name)
            assert.equal("catto", resp_body_json.custom_id)
          end)

          it("developer cannot update application with duplicate name", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = application_2.name,
                custom_id = "catto",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with name: 'myotherapp'", resp_body_json.fields.name)
          end)

          it("developer cannot update application with null custom_id", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = "mysecondapp",
                custom_id = ngx.null,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("required field missing", resp_body_json.fields.custom_id)
          end)

          it("developer cannot update application with duplicate custom_id", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = "mysecondapp",
                custom_id = application_2.custom_id,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("application already exists with custom_id: 'doggo_2'", resp_body_json.fields.custom_id)
          end)

          it("developer cannot update applications foreign keys", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                consumer = { id = utils.uuid() },
                developer = { id = utils.uuid() },
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.consumer.id, resp_body_json.consumer.id)
            assert.equal(application.developer.id, resp_body_json.developer.id)
          end)
        end)

        describe("DELETE", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can delete application", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/applications/" .. application.id,
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(204, res)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id,
              headers = {
                ["Cookie"] = cookie
              }
            })

            assert.res_status(404, res)
          end)
        end)
      end)

      describe("/applications/:applications/credentials", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("GET", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("returns 404", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(404, res)
          end)
        end)

        describe("POST", function()
          local application, cookie

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)
          end)


          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("returns 404", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(404, res)
          end)
        end)
      end)

      describe("/applications/:applications/application_instances", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("POST", function()
          local application, cookie, service_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            local body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))


          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))

          end)

          it("can POST a new application instance", function()

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(service_id, resp_body_json.service.id)
            assert.equal(1, resp_body_json.status)
          end)

          it("returns 400 with missing service id", function()

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {}
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(400, res)
          end)
        end)

        describe("GET", function()
          local application, cookie, service_id, service_id2

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "mysecondservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            local body = assert.res_status(201, res)
            service_id2 = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id2 },
            }))



            -- TODO: replace with db.insert?
            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(201, res)

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id2,

                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(201, res)
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          it("can GET list of application instances", function()

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances?size=1",
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              body = {
                service = {
                  id = service_id
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(1, resp_body_json.total)

            assert.equal(ngx.null, resp_body_json.next)
          end)
        end)
      end)

      describe("/applications/:applications/application_instances/:application_instances", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("GET", function()
          local application, cookie, service_id, application_instance_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))



            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            body = assert.res_status(201, res)
            application_instance_id = assert(cjson.decode(body).id)

          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))

          end)

          it("can GET a application instance", function()

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert(resp_body_json.service.id, service_id)
          end)
        end)

        describe("DELETE", function()
          local application, cookie, service_id, application_instance_id

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())


            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                custom_id = "doggo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/services",
              body = {
                name = "myfirstservice",
                host = "example.com",
                protocol = "http"
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            body = assert.res_status(201, res)
            service_id = assert(cjson.decode(body).id)

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/application_instances",
              body = {
                service = {
                  id = service_id,
                }
              },
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            body = assert.res_status(201, res)
            application_instance_id = assert(cjson.decode(body).id)

          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          it("can DELETE a application instance", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(204, res)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/application_instances/" .. application_instance_id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(404, res)
          end)
        end)
      end)

      describe("/application_services", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            license_path = "spec-ee/fixtures/mock_license.json",
            portal = true,
            portal_and_vitals_key = get_portal_and_vitals_key(),
            portal_auth = "basic-auth",
            portal_app_auth = "external-oauth2",
            portal_auto_approve = true,
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(db, {
            portal = true,
            portal_auth = "basic-auth",
            portal_auto_approve = true,
          })

          insert_files(db)

          portal_api_client = assert(ee_helpers.portal_api_client())

          close_clients(portal_api_client)
        end)

        lazy_teardown(function()
          helpers.stop_kong(nil, true, true)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client, admin_client)
        end)

        describe("GET", function()
          local cookie, service_id, developer

          lazy_setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            admin_client = assert(helpers.admin_client())

            local res = assert(admin_client:send {
              method = "POST",
              path = "/developers/roles",
              body = {
                name = "role1"
              },
              headers = {["Content-Type"] = "application/json"},
            })

            assert.res_status(201, res)

            local res = assert(admin_client:send {
              method = "POST",
              path = "/developers/roles",
              body = {
                name = "role2"
              },
              headers = {["Content-Type"] = "application/json"},
            })

            assert.res_status(201, res)

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role1" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            for i=1, 10 do
              local res = assert(admin_client:send {
                method = "POST",
                path = "/services",
                body = {
                  name = "myservice-" .. i,
                  host = "example.com",
                  protocol = "https"
                },
                headers = {
                  ["Content-Type"] = "application/json"
                }
              })

              local body = assert.res_status(201, res)

              if i % 2 == 0 then
                service_id = assert(cjson.decode(body).id)

                assert(db.plugins:insert({
                  config = {
                    display_name = "this service has application_registration",
                  },
                  name = "application-registration",
                  service = { id = service_id },
                }))

                local doc_config

                if i == 2 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": ["role1"]}
                    }]],
                    path = "specs/role1.json",
                  }
                end

                if i == 4 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": ["role2"]}
                    }]],
                    path = "specs/role2.json",
                  }
                end

                if i == 6 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {"readable_by": "*"}
                    }]],
                    path = "specs/star.json",
                  }
                end

                if i == 8 then
                  doc_config = {
                    contents = [[{
                      "x-headmatter": {}
                    }]],
                    path = "specs/noroles.json",
                  }
                end

                if doc_config then
                  local res = assert(admin_client:send {
                    method = "POST",
                    path = "/files",
                    body = doc_config,
                    headers = {["Content-Type"] = "application/json"}
                  })

                  assert.res_status(201, res)

                  local res = assert(admin_client:send {
                    method = "POST",
                    path = "/services/" .. service_id .. "/document_objects",
                    body = {
                      path = doc_config.path
                    },
                    headers = {["Content-Type"] = "application/json"}
                  })

                  assert.res_status(200, res)
                end
              end
            end
          end)

          lazy_teardown(function()
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
            assert(db:truncate('services'))
          end)

          it("can GET a list of services with Application Registration applied", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services?size=2",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(2, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(2, resp_body_json.total)

            assert.equal(ngx.null, resp_body_json.next)
          end)

          it("returns a permissioned service when the developer is assigned the proper role", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role1", "role2" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(5, resp_body_json.total)
          end)

          it("doesn't return a permissioned service when the role is removed from the developer", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(5, resp_body_json.total)

            local res = assert(admin_client:send {
              method = "PATCH",
              path = "/developers/" .. developer.id,
              body = {
                roles = { "role2" },
              },
              headers = {
                ["Content-Type"] = "application/json"
              }
            })

            assert.res_status(200, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/application_services",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)
          end)
        end)
      end)
    end)
  end
end
