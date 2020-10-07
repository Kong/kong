local cjson      = require "cjson"
local pl_stringx = require "pl.stringx"
local helpers    = require "spec.helpers"
local utils      = require "kong.tools.utils"
local ee_helpers = require "spec-ee.helpers"


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

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      describe("/applications", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
                    redirect_uri = "http://dog.com"
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
          local developer, developer_two

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "dale@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.developer

            local res = register_developer(portal_api_client, {
              email = "dev2@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"wow\"}",
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            developer_two = resp_body_json.developer
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
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("myfirstapp", resp_body_json.name)
            assert.equal("http://dog.com", resp_body_json.redirect_uri)
          end)

          it("ignores developer in body", function()
            assert.is_nil(db.consumers:select_by_username(developer.id .. "_new_app"))
            assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))

            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "new_app",
                redirect_uri = "http://dog.com",
                developer = { id = developer_two.id },
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(developer.id, resp_body_json.developer.id)
            assert(db.consumers:select_by_username(developer.id .. "_new_app"))
            assert.is_nil(db.consumers:select_by_username(developer_two.id .. "_new_app"))
          end)

          it("should return 409 when creating a pre-existing application", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
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
                redirect_uri = "http://dog.com"
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

          it("should return 409 when creating a pre-existing application with whitespace added to name", function()
            local cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("dale@konghq.com:kong"),
            }, true)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications",
              body = {
                name = "myfirstapp",
                redirect_uri = "http://dog.com"
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
                redirect_uri = "http://dog.com"
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
                redirect_uri = "http://dog.com"
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
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
                redirect_uri = "http://dog.com"
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
            assert.equal("http://dog.com", resp_body_json.redirect_uri)
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
                redirect_uri = "http://dog.com"
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
                redirect_uri = "http://dog.com",
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
                redirect_uri = "http://cat.com",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("mysecondapp", resp_body_json.name)
            assert.equal("http://cat.com", resp_body_json.redirect_uri)
          end)

          it("developer cannot update application with duplicate name", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                name = application_2.name,
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

          it("developer cannot update application with invalid 'redirect_uri'", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                redirect_uri = "bobobo",
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("missing host in url", resp_body_json.fields.redirect_uri)
          end)

          it("developer cannot update application with null 'redirect_uri'", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/applications/" .. application.id,
              body = {
                redirect_uri = ngx.null,
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)

            assert.equal("required field missing", resp_body_json.fields.redirect_uri)
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
                redirect_uri = "http://dog.com"
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
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            for i=1, 9 do
              res = assert(portal_api_client:send {
                method = "POST",
                path = "/applications/" .. application.id .. "/credentials",
                body = {},
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie
                }
              })

              assert.res_status(201, res)
            end
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("developer can retrieve credentials attached to application", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            for i, credential in ipairs(resp_body_json.data) do
              assert.equal(application.consumer.id, credential.consumer.id)
            end

            assert.equal(10, resp_body_json.total)
          end)

          it("paginates properly", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials?size=4",
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)
            assert.equal(4, resp_body_json.total)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = resp_body_json.next,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            resp_body_json = cjson.decode(body)

            assert.equal(2, resp_body_json.total)
            assert.equal(ngx.null, resp_body_json.next)
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
                redirect_uri = "http://dog.com"
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

          it("developer can create an application credential", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)

            assert.equal(application.consumer.id, resp_body_json.consumer.id)
          end)
        end)
      end)

      describe("/applications/:applications/credentials/:credentials", function()
        lazy_setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
          local application, cookie, credential

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
                redirect_uri = "http://dog.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            application = cjson.decode(body)

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            local body = assert.res_status(200, res)
            credential = cjson.decode(body).data[1]
          end)

          after_each(function()
            assert(db:truncate('basicauth_credentials'))
            assert(db:truncate('applications'))
            assert(db:truncate('consumers'))
            assert(db:truncate('developers'))
          end)

          it("can GET a specific credential", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials/" .. credential.id,
              headers = {
                ["Cookie"] = cookie,
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal(credential.id, resp_body_json.id)
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
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
                redirect_uri = "http://dog.com"
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
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)
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
                redirect_uri = "http://dog.com"
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
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

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
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id2 },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id2 },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

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
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
                redirect_uri = "http://dog.com"
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
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

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
                redirect_uri = "http://dog.com"
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
                enable_authorization_code = true,
              },
              name = "oauth2",
              service = { id = service_id },
            }))

            assert(db.plugins:insert({
              config = {
                display_name = "dope plugin",
              },
              name = "application-registration",
              service = { id = service_id },
            }))

            res = assert(portal_api_client:send {
              method = "GET",
              path = "/applications/" .. application.id .. "/credentials",
              body = {},
              headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookie
              }
            })

            assert.res_status(200, res)

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
            portal = true,
            portal_auth = "basic-auth",
            portal_app_auth = "kong-oauth2",
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
          local cookie, service_id

          lazy_setup(function()
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
                    enable_authorization_code = i % 4 == 0,
                    enable_implicit_grant = i % 4 ~= 0,
                  },
                  name = "oauth2",
                  service = { id = service_id },
                }))

                assert(db.plugins:insert({
                  config = {
                    display_name = "" .. i,
                  },
                  name = "application-registration",
                  service = { id = service_id },
                }))
              end
            end
          end)

          lazy_teardown(function()
            -- assert(db:truncate('basicauth_credentials'))
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
            assert.equal(5, resp_body_json.total)

            for i, v in ipairs(resp_body_json.data) do
              assert.equal(v.app_registration_config.display_name, v.name)
              assert.equal(v.auth_plugin_config.enable_authorization_code, tonumber(v.name) % 4 == 0)
              assert.equal(v.auth_plugin_config.enable_implicit_grant, tonumber(v.name) % 4 ~= 0)
            end
          end)

          it("can GET a list of services with Application Registration applied when non service oauth2 plugin (regression)", function()
            assert(db.plugins:insert({
              config = {
                enable_authorization_code = true,
                enable_implicit_grant = true,
              },
              name = "oauth2",
            }))

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

            for i, v in ipairs(resp_body_json.data) do
              assert.equal(v.app_registration_config.display_name, v.name)
              assert.equal(v.auth_plugin_config.enable_authorization_code, tonumber(v.name) % 4 == 0)
              assert.equal(v.auth_plugin_config.enable_implicit_grant, tonumber(v.name) % 4 ~= 0)
            end
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
            assert.equal(1, resp_body_json.total)
            assert.equal(ngx.null, resp_body_json.next)
          end)
        end)
      end)
    end)
  end
end
