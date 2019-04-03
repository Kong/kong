local helpers      = require "spec.helpers"
local cjson        = require "cjson"
local enums        = require "kong.enterprise_edition.dao.enums"
local utils        = require "kong.tools.utils"
local ee_jwt       = require "kong.enterprise_edition.jwt"
local time         = ngx.time
local uuid         = require("kong.tools.utils").uuid
local ee_helpers   = require "spec-ee.helpers"
local type         = type

local PORTAL_SESSION_CONF = "{ \"cookie_name\": \"portal_session\", \"secret\": \"super-secret\", \"cookie_secure\": false, \"storage\": \"kong\" }"
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

local function insert_files(dao)
  for i = 1, 10 do
    assert(dao.files:insert {
      name = "file-" .. i,
      contents = "i-" .. i,
      type = "partial",
      auth = i % 2 == 0 and true or false
    })

    assert(dao.files:insert {
      name = "file-page" .. i,
      contents = "i-" .. i,
      type = "page",
      auth = i % 2 == 0 and true or false
    })
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


local function configure_portal(dao)
  local workspaces = dao.workspaces:find_all({name = "default"})
  local workspace = workspaces[1]

  dao.workspaces:update({
    config = {
      portal = true,
    }
  }, {
    id = workspace.id,
  })
end


local function close_clients(portal_api_client, client)
  if client then
    client:close()
  end

  if portal_api_client then
    portal_api_client:close()
  end
end

local rbac_mode = {"off", "on"}

for _, strategy in helpers.each_strategy() do

   -- TODO DEVX: re-impliment once api endpoints are done
   if strategy == 'cassandra' or strategy == 'postgres' then
    return
  end

  for idx, rbac in ipairs(rbac_mode) do
    describe("#flaky Developer Portal - Portal API " .. strategy .. " (ENFORCE_RBAC = " .. rbac .. ")", function()
      local portal_api_client
      local client
      local bp, db, dao = helpers.get_db_utils(strategy)

      -- do not run tests for cassandra < 3
      if strategy == "cassandra" and dao.db.major_version_n < 3 then
        return
      end

      setup(function()
        dao:drop_schema()
        ngx.ctx.workspaces = {}
        dao:run_migrations()
      end)

      teardown(function()
        helpers.stop_kong()
        dao:drop_schema()
      end)

      -- this block is only run once, not for each rbac state
      if idx == 1 then
        describe("vitals", function ()
          setup(function()
            helpers.stop_kong()

            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              vitals     = true,
            }))

            configure_portal(dao)
          end)

          teardown(function()
            helpers.stop_kong()
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
            client = assert(helpers.admin_client())
          end)

          after_each(function()
            close_clients(portal_api_client, client)
          end)

          it("does not track internal proxies", function()
            local service_id = "00000000-0000-0000-0000-000000000001"

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/vitals/status_codes/by_service",
              query = {
                interval   = "minutes",
                service_id = service_id,
              }
            })

            res = assert.res_status(404, res)
            local json = cjson.decode(res)

            assert.same("Not found", json.message)
          end)

          it("does not report metrics for internal proxies", function()
            local service_id = "00000000-0000-0000-0000-000000000001"

            local pres = assert(portal_api_client:send {
              method = "GET",
              path = "/files"
            })

            assert.res_status(200, pres)

            ngx.sleep(11) -- flush interval for vitals is at 10 seconds so wait
                          -- 11 to ensure we get metrics for the bucket this
                          -- request would live in.

            local res = assert(client:send {
              method = "GET",
              path = "/vitals/cluster",
              query = {
                interval   = "seconds",
                service_id = service_id,
              }
            })

            res = assert.res_status(200, res)

            local json = cjson.decode(res)
            for k,v in pairs(json.stats.cluster) do
              assert.equal(0, v[7]) -- ensure that each `requests_proxy_total` is
                                    -- equal to 0, this means that there were no
                                    -- proxy requests during this timeframe
            end
          end)
        end)
      end

      describe("CORS", function()
        setup(function()
          helpers.stop_kong()
          dao:truncate_tables()

          insert_files(dao)
          configure_portal(dao)

        end)

         after_each(function()
          close_clients(portal_api_client)
          helpers.stop_kong()
        end)

         describe("single portal_cors_origins", function()
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_cors_origins = "http://foo.example"
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_cors_origins = "http://foo.example, http://bar.example"
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_cors_origins = "*"
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_gui_protocol = "http",
              portal_gui_host = "example.foo"
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_gui_protocol = "http",
              portal_gui_host = "example.foo",
              portal_gui_use_subdomains = true,
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
          setup(function()
            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              enforce_rbac = rbac,
              portal_gui_use_subdomains = true,
            }))

             portal_api_client = assert(ee_helpers.portal_api_client())
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
        setup(function()
          helpers.stop_kong()
          dao:truncate_tables()

          insert_files(dao)
          configure_portal(dao)


          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            enforce_rbac = rbac,
          }))
        end)

        teardown(function()
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

            assert.equal(20, json.total)
            assert.equal(20, #json.data)
          end)

          it("retrieves only unauthenticated files", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files/unauthenticated",
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.equal(10, json.total)
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

            assert.equal(5, json.total)
            assert.equal(5, #json.data)
            for key, value in ipairs(json.data) do
              assert.equal(false, value.auth)
            end
          end)
        end)
      end)

      describe("/register", function()
        describe("basic-auth", function()
          setup(function()
            helpers.stop_kong()
            assert(db:truncate())

            assert(helpers.start_kong({
              database = strategy,
              portal = true,
              portal_auth = "basic-auth",
              enforce_rbac = rbac,
              portal_session_conf = PORTAL_SESSION_CONF,
              admin_gui_url = "http://localhost:8080",
            }))

            configure_portal(dao)
          end)

          teardown(function()
            helpers.stop_kong()
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
          end)

          after_each(function()
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns a 400 if email is invalid format", function()
              local res = register_developer(portal_api_client, {
                email = "grucekonghq.com",
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: missing '@' symbol", message)
            end)

            it("returns a 400 if email is invalid type", function()
              local res = register_developer(portal_api_client, {
                email = 9000,
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: must be a string", message)
            end)

            it("returns a 400 if email is missing", function()
              local res = register_developer(portal_api_client, {
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: missing", message)
            end)

            it("returns a 400 if meta is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                password = "kong",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param is missing", message)
            end)

            it("returns a 400 if meta is invalid", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                password = "kong",
                meta = "{weird}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param is invalid", message)
            end)

            it("returns a 400 if meta.full_name key is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                password = "kong",
                meta = "{\"something_else\":\"not full name\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param missing key: 'full_name'", message)
            end)

            it("registers a developer and set status to pending", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                password = "iheartkong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              }
            )
              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)
              local credential = resp_body_json.credential
              local consumer = resp_body_json.consumer

              assert.is_true(utils.is_valid_uuid(consumer.id))

              assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)
              assert.equal(enums.CONSUMERS.STATUS.PENDING, consumer.status)

              assert.equal(consumer.id, credential.consumer_id)

              local expected_email_res = {
                error = {
                  count = 0,
                  emails = {}
                },
                sent = {
                  count = 1,
                  emails = {
                    ["admin@example.com"] = true,
                  }
                },
                smtp_mock = true,
              }

              assert.same(expected_email_res, resp_body_json.email)
            end)
          end)
        end)

        describe("key-auth", function()
          setup(function()
            helpers.stop_kong()
            assert(db:truncate())

            assert(helpers.start_kong({
              database = strategy,
              portal = true,
              portal_auth = "key-auth",
              enforce_rbac = rbac,
              portal_session_conf = PORTAL_SESSION_CONF,
              admin_gui_url = "http://localhost:8080",
            }))

            configure_portal(dao)
          end)

          teardown(function()
            helpers.stop_kong()
          end)

          before_each(function()
            portal_api_client = assert(ee_helpers.portal_api_client())
          end)

          after_each(function()
            close_clients(portal_api_client)
          end)

          describe("POST", function()
            it("returns a 400 if email is invalid format", function()
              local res = register_developer(portal_api_client, {
                email = "grucekonghq.com",
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: missing '@' symbol", message)
            end)

            it("returns a 400 if email is invalid type", function()
              local res = register_developer(portal_api_client, {
                email = 9000,
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: must be a string", message)
            end)

            it("returns a 400 if email is missing", function()
              local res = register_developer(portal_api_client, {
                key = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid email: missing", message)
            end)

            it("returns a 400 if meta is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param is missing", message)
            end)

            it("returns a 400 if meta is invalid", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
                meta = "{weird}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param is invalid", message)
            end)

            it("returns a 400 if meta.full_name key is missing", function()
              local res = register_developer(portal_api_client, {
                email = "gruce@konghq.com",
                key = "kong",
                meta = "{\"something_else\":\"not full name\"}",
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("meta param missing key: 'full_name'", message)
            end)

            it("registers a developer and set status to pending", function()
              local res = register_developer(portal_api_client, {
                email = "noob@konghq.com",
                key = "iheartkong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              }
            )
              local body = assert.res_status(201, res)
              local resp_body_json = cjson.decode(body)
              local credential = resp_body_json.credential
              local consumer = resp_body_json.consumer

              assert.is_true(utils.is_valid_uuid(consumer.id))

              assert.equal(enums.CONSUMERS.TYPE.DEVELOPER, consumer.type)
              assert.equal(enums.CONSUMERS.STATUS.PENDING, consumer.status)

              assert.equal(consumer.id, credential.consumer_id)

              local expected_email_res = {
                error = {
                  count = 0,
                  emails = {}
                },
                sent = {
                  count = 1,
                  emails = {
                    ["admin@example.com"] = true,
                  }
                },
                smtp_mock = true,
              }

              assert.same(expected_email_res, resp_body_json.email)
            end)
          end)
        end)
      end)

      describe("Authenticated Routes [basic-auth]", function()
        local approved_developer

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          configure_portal(dao)
          insert_files(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          local pending_developer = bp.consumers:insert {
            username = "dale",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.PENDING,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "dale",
            password    = "kong",
            consumer_id = pending_developer.id,
          })

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.consumer
          close_clients(portal_api_client)
        end)

        teardown(function()
          helpers.stop_kong()
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          close_clients(portal_api_client)
        end)

        describe("/auth [basic-auth]", function()
          describe("GET", function()
            it("returns 401 when consumer is not approved", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ status = 1, label = "PENDING" }, json)

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
              assert.same({ status = 1, label = "PENDING" }, json)
            end)

            it("returns 403 with invalid password ", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:weirdo"),
              })

              local body = assert.res_status(403, res)
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
              assert.equals("Unauthorized", json.message)
            end)

            it("returns 403 with invalid username ", function()
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("derp:kong"),
              })

              local body = assert.res_status(403, res)
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
              assert.equals("Unauthorized", json.message)
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

              assert.equals("Unauthorized", json.message)
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

              assert.equal(20, json.total)
              assert.equal(20, #json.data)
            end)
          end)

          describe("POST, PATCH, PUT", function ()
            it("does not allow forbidden methods", function()
              local cookie = authenticate(portal_api_client, "basic-auth", true)
              local res_put = assert(portal_api_client:send {
                method = "PUT",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_put)

              local res_patch = assert(portal_api_client:send {
                method = "PATCH",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_patch)

              local res_post = assert(portal_api_client:send {
                method = "POST",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_post)
            end)
          end)
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

              assert.equal("Invalid email: missing '@' symbol", message)
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

              local secrets = db.consumer_reset_secrets:select_all()
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

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

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

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

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

              local pending = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id,
                status = enums.TOKENS.STATUS.PENDING,
              })

              assert.equal(1, #pending)
              db.consumer_reset_secrets:delete({ id = pending[1].id })

              local invalidated = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id,
                status = enums.TOKENS.STATUS.INVALIDATED,
              })

              assert.equal(1, #invalidated)
              db.consumer_reset_secrets:delete({ id = invalidated[1].id })

              assert.not_equal(pending[1].secret, invalidated[1].secret)
            end)
          end)
        end)

        describe("/reset-password [basic-auth]", function()
          local secret
          local approved_developer

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "kongkong@konghq.com",
              password = "wowza",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            approved_developer = resp_body_json.consumer

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = approved_developer.email,
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local rows = db.consumer_reset_secrets:select_all({
              consumer_id = approved_developer.id,
              status = enums.TOKENS.STATUS.PENDING,
            })

            secret = rows[1].secret
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
                  password = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Invalid JWT", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
              local bad_jwt = ee_jwt.generate_JWT(claims, "bad_secret")

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = bad_jwt,
                  password = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 401 if token is expired", function()
              local claims = {id = approved_developer.id, exp = time() - 100000}
              local expired_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = expired_jwt,
                  password = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Expired JWT", message)
            end)

            it("should return 401 if token contains non-existent developer", function()
              local claims = {id = uuid(), exp = time() + 100000}
              local random_uuid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = random_uuid_jwt,
                  password = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(401, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("Unauthorized", message)
            end)

            it("should return 400 if called without a password", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  token = valid_jwt,
                  password = "",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              local body = assert.res_status(400, res)
              local resp_body_json = cjson.decode(body)
              local message = resp_body_json.message

              assert.equal("password is required", message)
            end)

            it("should return 200 if called with a valid token, ignoring email_or_id param (regression)", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
              local valid_jwt = ee_jwt.generate_JWT(claims, secret)

              local res = assert(portal_api_client:send {
                method = "POST",
                path = "/reset-password",
                body = {
                  email_or_id = "this_will_be_ignored",
                  token = valid_jwt,
                  password = "derp",
                },
                headers = {["Content-Type"] = "application/json"}
              })

              assert.res_status(200, res)

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

              -- token is consumed
              assert.equal(1, #rows)
              assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

              -- old password fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("kongkong@konghq.com:wowza"),
              })

              local body = assert.res_status(403, res)
              local json = cjson.decode(body)
              assert.equals("Invalid authentication credentials", json.message)

              local cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              -- new password auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("kongkong@konghq.com:derp"),
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

        describe("/validate-reset [basic-auth]", function()
          local secret

          setup(function()
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

            local rows = db.consumer_reset_secrets:select_all({
              consumer_id = approved_developer.id,
              status = enums.TOKENS.STATUS.PENDING,
            })

            secret = rows[1].secret
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

              assert.equal("Invalid JWT", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
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
              local claims = {id = approved_developer.id, exp = time() - 100000}
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

              assert.equal("Expired JWT", message)
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
              local claims = {id = approved_developer.id, exp = time() + 100000}
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

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "devdevdev@konghq.com",
              password = "developer",
              meta = "{\"full_name\":\"Kong Dev\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.consumer

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("devdevdev@konghq.com:developer"),
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

        describe("/developer/password [basic-auth]", function()
          local cookie

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "passwordchange@konghq.com",
              password = "changeme",
              meta = "{\"full_name\":\"Mario\"}",
            })

            assert.res_status(201, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:changeme"),
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:hunter1"),
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

            it("updates the password", function()
              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  password = "hunter1",
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:changeme")
              })

              cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)
              assert.res_status(403, res)

              -- new password auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("passwordchange@konghq.com:hunter1"),
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

        describe("/developer/email [basic-auth]", function()
          local other_developer
          local cookie

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "changeme@konghq.com",
              password = "pancakes",
              meta = "{\"full_name\":\"Bowser\"}",
            })

            assert.res_status(201, res)

            res = register_developer(portal_api_client, {
              email = "otherdeveloper@konghq.com",
              password = "rad",
              meta = "{\"full_name\":\"Toad\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            other_developer = resp_body_json.consumer

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("changeme@konghq.com:pancakes"),
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:pancakes"),
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
              ["Authorization"] = "Basic " .. ngx.encode_base64("otherdeveloper@konghq.com:rad"),
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
              local message = resp_body_json.message

              assert.equal("Invalid email: missing '@' symbol", message)
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
              local message = resp_body_json.username

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

              assert.res_status(204, res)

              -- old email fails
              local res = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("changeme@konghq.com:pancakes"),
              })

              assert.res_status(403, res)
              cookie = res.headers["Set-Cookie"]
              assert.is_nil(cookie)

              -- new email auths
              cookie = authenticate(portal_api_client, {
                ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:pancakes"),
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
              assert.equal("new_email@whodis.com", resp_body_json.username)
            end)
          end)
        end)

        describe("/developer/meta [basic-auth]", function()
          local cookie

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "metachange@konghq.com",
              password = "bloodsport",
              meta = "{\"full_name\":\"I will change\"}",
            })

            assert.res_status(201, res)

            cookie = authenticate(portal_api_client, {
              ["Authorization"] = "Basic " .. ngx.encode_base64("metachange@konghq.com:bloodsport"),
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
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

          describe("PATCH", function()
            it("updates the meta", function()
              local new_meta = "{\"full_name\":\"KONG!!!\"}"

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(204, res)

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

            it("ignores keys that are not in the current meta", function()
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
                method = "PATCH",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

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

        describe("/credentials/:plugin [basic-auth]", function()
          local credential
          local credential_key_auth
          local cookie

          setup(function()
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
        end)

        describe("/config [basic-auth]", function()
          local cookie

          setup(function()
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
      end)

      describe("Authenticated Routes [key-auth]", function()
        local approved_developer

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          configure_portal(dao)
          insert_files(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            portal_auth = "key-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          local pending_developer = bp.consumers:insert {
            username = "dale",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.PENDING,
          }

          assert(dao.keyauth_credentials:insert {
            key         = "kong",
            consumer_id = pending_developer.id,
          })

          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "key-auth")
          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.consumer
          close_clients(portal_api_client)
        end)

        teardown(function()
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
              assert.same({ status = 1, label = "PENDING" }, json)

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
              assert.same({ status = 1, label = "PENDING" }, json)
            end)

            it("returns 403 with invalid apikey ", function()
              local res = authenticate(portal_api_client, {
                ["apikey"] = "nope",
              })

              local body = assert.res_status(403, res)
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
              assert.equals("Unauthorized", json.message)
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

              assert.equals("Unauthorized", json.message)
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

              assert.equal(20, json.total)
              assert.equal(20, #json.data)
            end)
          end)

          describe("POST, PATCH, PUT", function ()
            it("does not allow forbidden methods", function()
              local cookie = authenticate(portal_api_client, "key-auth", true)
              local res_put = assert(portal_api_client:send {
                method = "PUT",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_put)

              local res_patch = assert(portal_api_client:send {
                method = "PATCH",
                path = "/files",
                headers = {
                  ["Cookie"] = cookie
                },
              })

              assert.res_status(405, res_patch)

              local res_post = assert(portal_api_client:send {
                method = "POST",
                path = "/files",
                headers = {
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

              assert.equal("Invalid email: missing '@' symbol", message)
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

              local reset_secrets = db.consumer_reset_secrets:select_all()
              assert.equals(0, #reset_secrets)
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

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

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

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

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

              local pending = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id,
                status = enums.TOKENS.STATUS.PENDING,
              })

              assert.equal(1, #pending)
              db.consumer_reset_secrets:delete({ id = pending[1].id })

              local invalidated = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id,
                status = enums.TOKENS.STATUS.INVALIDATED,
              })

              assert.equal(1, #invalidated)
              db.consumer_reset_secrets:delete({ id = invalidated[1].id })

              assert.not_equal(pending[1].secret, invalidated[1].secret)
            end)
          end)
        end)

        describe("/reset-password [key-auth]", function()
          local secret
          local approved_developer

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "kongkong@konghq.com",
              key = "wowza",
              meta = "{\"full_name\":\"1337\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            approved_developer = resp_body_json.consumer

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = approved_developer.email,
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local rows = db.consumer_reset_secrets:select_all({
              consumer_id = approved_developer.id,
              status = enums.TOKENS.STATUS.PENDING,
            })

            secret = rows[1].secret
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

              assert.equal("Invalid JWT", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
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
              local claims = {id = approved_developer.id, exp = time() - 100000}
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

              assert.equal("Expired JWT", message)
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
              local claims = {id = approved_developer.id, exp = time() + 100000}
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
              local claims = {id = approved_developer.id, exp = time() + 100000}
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

              local rows = db.consumer_reset_secrets:select_all({
                consumer_id = approved_developer.id
              })

              -- token is consumed
              assert.equal(1, #rows)
              assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

              -- old key fails
              local res = authenticate(portal_api_client, {
                ["apikey"] = "wowza",
              })

              local body = assert.res_status(403, res)
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

          setup(function()
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

            local rows = db.consumer_reset_secrets:select_all({
              consumer_id = approved_developer.id,
              status = enums.TOKENS.STATUS.PENDING,
            })

            secret = rows[1].secret
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

              assert.equal("Invalid JWT", message)
            end)

            it("should return 401 if token is signed with an invalid secret", function()
              local claims = {id = approved_developer.id, exp = time() + 100000}
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
              local claims = {id = approved_developer.id, exp = time() - 100000}
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

              assert.equal("Expired JWT", message)
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
              local claims = {id = approved_developer.id, exp = time() + 100000}
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

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "devdevdev@konghq.com",
              key = "developer",
              meta = "{\"full_name\":\"Kong Dev\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            developer = resp_body_json.consumer

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

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "passwordchange@konghq.com",
              key = "changeme",
              meta = "{\"full_name\":\"Mario\"}",
            })

            assert.res_status(201, res)

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "changeme",
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
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
              assert.res_status(403, res)

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

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "changeme@konghq.com",
              key = "pancakes",
              meta = "{\"full_name\":\"Bowser\"}",
            })

            assert.res_status(201, res)

            local res = register_developer(portal_api_client, {
              email = "otherdeveloper@konghq.com",
              key = "rad",
              meta = "{\"full_name\":\"Toad\"}",
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)
            other_developer = resp_body_json.consumer

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "pancakes",
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
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
              local message = resp_body_json.message

              assert.equal("Invalid email: missing '@' symbol", message)
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
              local message = resp_body_json.username

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

              assert.res_status(204, res)

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
              assert.equal("new_email@whodis.com", resp_body_json.username)
            end)
          end)
        end)

        describe("/developer/meta [key-auth]", function()
          local cookie

          setup(function()
            portal_api_client = assert(ee_helpers.portal_api_client())

            local res = register_developer(portal_api_client, {
              email = "metachange@konghq.com",
              key = "bloodsport",
              meta = "{\"full_name\":\"I will change\"}",
            })

            assert.res_status(201, res)

            cookie = authenticate(portal_api_client, {
              ["apikey"] = "bloodsport",
            }, true)

            close_clients(portal_api_client)
          end)

          teardown(function()
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

          describe("PATCH", function()
            it("updates the meta", function()
              local new_meta = "{\"full_name\":\"KONG!!!\"}"

              local res = assert(portal_api_client:send {
                method = "PATCH",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                }
              })

              assert.res_status(204, res)

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

            it("ignores keys that are not in the current meta", function()
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
                method = "PATCH",
                body = {
                  meta = new_meta
                },
                path = "/developer/meta",
                headers = {
                  ["Content-Type"] = "application/json",
                  ["Cookie"] = cookie,
                },
              })

              assert.res_status(204, res)

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

          setup(function()
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
        end)

        describe("/config [key-auth]", function()
          local cookie

          setup(function()
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

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            vitals  = false,
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(dao)
          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          assert.res_status(201, res)

          cookie = authenticate(portal_api_client, "basic-auth", true)

          close_clients(portal_api_client)
        end)

        teardown(function()
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

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())

          assert(helpers.start_kong({
            database   = strategy,
            portal_session_conf = PORTAL_SESSION_CONF,
            portal = true,
            vitals  = true,
            portal_auth = "basic-auth",
            enforce_rbac = rbac,
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(dao)
          portal_api_client = assert(ee_helpers.portal_api_client())

          local res = register_developer(portal_api_client, "basic-auth")
          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          approved_developer = resp_body_json.consumer

          cookie = authenticate(portal_api_client, "basic-auth", true)

          close_clients(portal_api_client)
        end)

        teardown(function()
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
                message = "Invalid query params: interval must be 'minutes' or 'seconds'",
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
                  entity_id   = approved_developer.id,
                  entity_type = "consumer",
                  interval    = "seconds",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_total" },
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
                  entity_id   = approved_developer.id,
                  entity_type = "consumer",
                  interval    = "minutes",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_total" },
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
                message = "Invalid query params: interval must be 'minutes' or 'seconds'",
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
                  entity_id   = approved_developer.id,
                  entity_type = "consumer_route",
                  interval    = "seconds",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_route_total" },
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
                  entity_id   = approved_developer.id,
                  entity_type = "consumer_route",
                  interval    = "minutes",
                  level       = "cluster",
                  stat_labels = { "status_codes_per_consumer_route_total" },
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
                message = "Invalid query params: interval must be 'minutes' or 'seconds'",
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
    end)
  end
end
