local helpers      = require "spec.helpers"
local cjson        = require "cjson"
local enums        = require "kong.enterprise_edition.dao.enums"
local utils        = require "kong.tools.utils"
local ee_jwt       = require "kong.enterprise_edition.jwt"
local time         = ngx.time
local uuid         = require("kong.tools.utils").uuid
local ee_helpers   = require "spec-ee.helpers"


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


local rbac_mode = {"off"}

-- TODO: Cassandra
for _, strategy in helpers.each_strategy('postgres') do
  for idx, rbac in ipairs(rbac_mode) do
    describe("Developer Portal - Portal API (RBAC = " .. rbac .. ")", function()
      local bp
      local db
      local dao
      local client
      local portal_api_client
      local consumer_approved

      setup(function()
        bp, db, dao = helpers.get_db_utils(strategy)
      end)

      teardown(function()
        helpers.stop_kong()
      end)

      -- this block is only run once, not for each rbac state
      if idx == 1 then
        describe("vitals", function ()

          before_each(function()
            helpers.stop_kong()
            helpers.register_consumer_relations(dao)

            assert(helpers.start_kong({
              database   = strategy,
              portal     = true,
              vitals     = true,
            }))

            client = assert(helpers.admin_client())
            portal_api_client = assert(ee_helpers.portal_api_client())
            configure_portal(dao)
          end)

          after_each(function()
            if client then
              client:close()
            end

            if portal_api_client then
              portal_api_client:close()
            end
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

      describe("/files without auth", function()
        before_each(function()
          helpers.stop_kong()

          dao:truncate_tables()

          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac = rbac,
          }))

          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("GET", function()
          before_each(function()
            insert_files(dao)
            configure_portal(dao)
          end)

          teardown(function()
            db:truncate()
          end)

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

      describe("/files with auth", function()
        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          insert_files(dao)
          configure_portal(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            portal_auth = "basic-auth",
            rbac = rbac,
            portal_auth_config = "{ \"hide_credentials\": true }",
          }))

          local consumer_pending = bp.consumers:insert {
            username = "dale",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.PENDING,
          }

          consumer_approved = bp.consumers:insert {
            username = "hawk",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.APPROVED,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "dale",
            password    = "kong",
            consumer_id = consumer_pending.id,
          })

          assert(dao.basicauth_credentials:insert {
            username    = "hawk",
            password    = "kong",
            consumer_id = consumer_approved.id,
          })
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("GET", function()
          it("returns 401 when unauthenticated", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
            })

            assert.res_status(401, res)
          end)

          it("returns 401 when consumer is not approved", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
              headers = {
                ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
              },
            })

            local body = assert.res_status(401, res)
            local json = cjson.decode(body)
            assert.same({ status = 1, label = "PENDING" }, json)
          end)

          it("retrieves files with an approved consumer", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/files",
              headers = {
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
            local consumer_auth_header = "Basic " .. ngx.encode_base64("hawk:kong")

            local res_put = assert(portal_api_client:send {
              method = "PUT",
              path = "/files",
              headers = {
                ["Authorization"] = consumer_auth_header,
              },
            })

            assert.res_status(405, res_put)

            local res_patch = assert(portal_api_client:send {
              method = "PATCH",
              path = "/files",
              headers = {
                ["Authorization"] = consumer_auth_header,
              },
            })

            assert.res_status(405, res_patch)

            local res_post = assert(portal_api_client:send {
              method = "POST",
              path = "/files",
              headers = {
                ["Authorization"] = consumer_auth_header,
              },
            })

            assert.res_status(405, res_post)
          end)
        end)
      end)

      describe("/register", function()
        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            portal_auth = "basic-auth",
            rbac = rbac,
            portal_auth_config = "{ \"hide_credentials\": true }",
            admin_gui_url = "http://localhost:8080",
          }))

          configure_portal(dao)
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("POST", function()
          it("returns a 400 if email is invalid format", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = "grucekonghq.com",
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("Invalid email: missing '@' symbol", message)
          end)

          it("returns a 400 if email is invalid type", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = 9000,
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("Invalid email: must be a string", message)
          end)

          it("returns a 400 if email is missing", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("Invalid email: missing", message)
          end)

          it("returns a 400 if meta is missing", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = "gruce@konghq.com",
                password = "kong",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("meta param is missing", message)
          end)

          it("returns a 400 if meta is invalid", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = "gruce@konghq.com",
                password = "kong",
                meta = "{weird}",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("meta param is invalid", message)
          end)

          it("returns a 400 if meta.full_name key is missing", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = "gruce@konghq.com",
                password = "kong",
                meta = "{\"something_else\":\"not full name\"}",
              },
              headers = {["Content-Type"] = "application/json"},
            })

            local body = assert.res_status(400, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("meta param missing key: 'full_name'", message)
          end)

          it("registers a developer and set status to pending", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/register",
              body = {
                email = "gruce@konghq.com",
                password = "kong",
                meta = "{\"full_name\":\"I Like Turtles\"}"
              },
              headers = {["Content-Type"] = "application/json"}
            })

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

      describe("/forgot-password", function()
        local developer

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          ee_helpers.register_token_statuses(dao)
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            rbac = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })


          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)

          developer = resp_body_json.consumer

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

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

            local count = dao.consumer_reset_secrets:count()
            assert.equals(0, count)
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

            local rows = dao.consumer_reset_secrets:find_all({
              consumer_id = developer.id
            })

            assert.is_string(rows[1].secret)
            assert.equal(1, #rows)
          end)

          it("should invalidate the previous secret if called twice", function()
            assert(dao.consumer_reset_secrets:truncate())

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/forgot-password",
              body = {
                email = "gruce@konghq.com",
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local rows = dao.consumer_reset_secrets:find_all({
              consumer_id = developer.id
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

            local rows = dao.consumer_reset_secrets:find_all({
              consumer_id = developer.id
            })

            assert.equal(2, #rows)

            local pending_count = 0
            local invalidated_count = 0

            for _, row in ipairs(rows) do
              if row.status == enums.TOKENS.STATUS.PENDING then
                pending_count = pending_count + 1
              end

              if row.status == enums.TOKENS.STATUS.INVALIDATED then
                invalidated_count = invalidated_count + 1
              end
            end

            assert.not_equal(rows[1].secret, rows[2].secret)
            assert.equal(1, pending_count)
            assert.equal(1, invalidated_count)
          end)
        end)
      end)

      describe("/reset-password (basic-auth)", function()
        local developer
        local secret

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)
          ee_helpers.register_token_statuses(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            rbac = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
            smtp_mock = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)

          developer = resp_body_json.consumer

          res = assert(portal_api_client:send {
            method = "POST",
            path = "/forgot-password",
            body = {
              email = "gruce@konghq.com",
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(200, res)

          local rows = dao.consumer_reset_secrets:find_all({
            consumer_id = developer.id
          })

          secret = rows[1].secret

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
            local claims = {id = developer.id, exp = time() + 100000}
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
            local claims = {id = developer.id, exp = time() - 100000}
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
            local claims = {id = developer.id, exp = time() + 100000}
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
            local claims = {id = developer.id, exp = time() + 100000}
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

            local rows = dao.consumer_reset_secrets:find_all({
              consumer_id = developer.id
            })

            -- token is consumed
            assert.equal(1, #rows)
            assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

            -- old password fails
            res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(403, res)

            -- new password auths
            res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:derp"),
              }
            })

            assert.res_status(200, res)
          end)
        end)
      end)

      describe("/validate-reset (basic-auth)", function()
        local developer
        local secret

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)
          ee_helpers.register_token_statuses(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            rbac = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)

          developer = resp_body_json.consumer

          res = assert(portal_api_client:send {
            method = "POST",
            path = "/forgot-password",
            body = {
              email = "gruce@konghq.com",
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(200, res)

          local rows = dao.consumer_reset_secrets:find_all({
            consumer_id = developer.id
          })

          secret = rows[1].secret

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
            local claims = {id = developer.id, exp = time() + 100000}
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
            local claims = {id = developer.id, exp = time() - 100000}
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
            local claims = {id = developer.id, exp = time() + 100000}
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

      describe("/reset-password (key-auth)", function()
        local developer
        local secret

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)
          ee_helpers.register_token_statuses(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            rbac = rbac,
            portal_auth = "key-auth",
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              key = "kongstrong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)

          developer = resp_body_json.consumer

          res = assert(portal_api_client:send {
            method = "POST",
            path = "/forgot-password",
            body = {
              email = "gruce@konghq.com",
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(200, res)

          local rows = dao.consumer_reset_secrets:find_all({
            consumer_id = developer.id
          })

          secret = rows[1].secret

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
            local claims = {id = developer.id, exp = time() + 100000}
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
            local claims = {id = developer.id, exp = time() - 100000}
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

          it("should return 400 if called without a password", function()
            local claims = {id = developer.id, exp = time() + 100000}
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

          it("should return 200 if called with a valid token", function()
            local claims = {id = developer.id, exp = time() + 100000}
            local valid_jwt = ee_jwt.generate_JWT(claims, secret)

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/reset-password",
              body = {
                token = valid_jwt,
                key = "derp",
              },
              headers = {["Content-Type"] = "application/json"}
            })

            assert.res_status(200, res)

            local rows = dao.consumer_reset_secrets:find_all({
              consumer_id = developer.id
            })

            -- token is consumed
            assert.equal(1, #rows)
            assert.equal(enums.TOKENS.STATUS.CONSUMED, rows[1].status)

            -- old key fails
            res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer?apikey=kongstrong",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(403, res)

            -- new key auths
            res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer?apikey=derp",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(200, res)
          end)
        end)
      end)


      describe("/validate-reset (key-auth)", function()
        local developer
        local secret

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)
          ee_helpers.register_token_statuses(dao)

          assert(helpers.start_kong({
            database = strategy,
            portal = true,
            rbac = rbac,
            portal_auth = "key-auth",
            portal_auto_approve = "on",
            admin_gui_url = "http://localhost:8080",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              key = "kongstrong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)

          developer = resp_body_json.consumer

          res = assert(portal_api_client:send {
            method = "POST",
            path = "/forgot-password",
            body = {
              email = "gruce@konghq.com",
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(200, res)

          local rows = dao.consumer_reset_secrets:find_all({
            consumer_id = developer.id
          })

          secret = rows[1].secret

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
            local claims = {id = developer.id, exp = time() + 100000}
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
            local claims = {id = developer.id, exp = time() - 100000}
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
            local claims = {id = developer.id, exp = time() + 100000}
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

      describe("/developer", function()
        local developer

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          developer = resp_body_json.consumer

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("GET", function()
          it("returns the authenticated developer", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local res_developer = resp_body_json

            assert.same(res_developer, developer)
          end)
        end)

        describe("DELETE", function()
          it("deletes authenticated developer", function()
            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(204, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(403, res)
          end)
        end)
      end)

      describe("/developer/password [basic-auth]", function()

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("PATCH", function()
          it("returns 400 if patched with no password", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {},
              path = "/developer/password",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(204, res)

            -- old password fails
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(403, res)

            -- new password auths
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:hunter1"),
              }
            })

            assert.res_status(200, res)
          end)
        end)
      end)

      describe("/developer/password [key-auth]", function()

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "key-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              key = "myKeeeeeey",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("PATCH", function()
          it("returns 400 if patched with no key", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {},
              path = "/developer/password?apikey=myKeeeeeey",
              headers = {
                ["Content-Type"] = "application/json",
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
              path = "/developer/password?apikey=myKeeeeeey",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(204, res)

            -- old key fails
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer?apikey=myKeeeeeey",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(403, res)

            -- new key auths
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer?apikey=hunter1",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(200, res)
          end)
        end)
      end)

      describe("/developer/email [basic-auth]", function()
        local developer2

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}",
            },
            headers = {["Content-Type"] = "application/json"},
          })

          assert.res_status(201, res)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "fancypants@konghq.com",
              password = "mowmow",
              meta = "{\"full_name\":\"Old Gregg\"}",
            },
            headers = {["Content-Type"] = "application/json"},
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          developer2 = resp_body_json.consumer

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("PATCH", function()
          it("returns 400 if patched with an invalid email", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {
                email = "emailol.com",
              },
              path = "/developer/email",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
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
                email = developer2.email,
              },
              path = "/developer/email",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.username

            assert.equal("already exists with value 'fancypants@konghq.com'", message)
          end)

          it("updates both email and username from passed email", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {
                email = "new_email@whodis.com",
              },
              path = "/developer/email",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(204, res)

            -- old email fails
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(403, res)


            -- new email succeeds
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            assert.equal("new_email@whodis.com", resp_body_json.email)
            assert.equal("new_email@whodis.com", resp_body_json.username)
          end)
        end)
      end)

      describe("/developer/email [key-auth]", function()
        local developer2

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "key-auth",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              key = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "fancypants@konghq.com",
              key = "mowmow",
              meta = "{\"full_name\":\"Old Gregg\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(201, res)
          local resp_body_json = cjson.decode(body)
          developer2 = resp_body_json.consumer

          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("PATCH", function()
          it("returns 400 if patched with an invalid key", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {
                email = "emailol.com",
              },
              path = "/developer/email?apikey=wrongKey",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(403, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.message

            assert.equal("Invalid authentication credentials", message)
          end)

          it("returns 409 if patched with an email that already exists", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {
                email = developer2.email,
              },
              path = "/developer/email?apikey=kong",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            local body = assert.res_status(409, res)
            local resp_body_json = cjson.decode(body)
            local message = resp_body_json.username

            assert.equal("already exists with value 'fancypants@konghq.com'", message)
          end)

          it("updates both email and username from passed email", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              body = {
                email = "new_email@whodis.com",
              },
              path = "/developer/email?apikey=kong",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })

            assert.res_status(204, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer?apikey=kong",
              headers = {
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

      describe("/developer/meta", function()

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          portal_api_client = assert(ee_helpers.portal_api_client())
          configure_portal(dao)

          local res = assert(portal_api_client:send {
            method = "POST",
            path = "/register",
            body = {
              email = "gruce@konghq.com",
              password = "kong",
              meta = "{\"full_name\":\"I Like Turtles\"}"
            },
            headers = {["Content-Type"] = "application/json"}
          })

          assert.res_status(201, res)
          portal_api_client:close()
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(204, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
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
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            assert.res_status(204, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/developer",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local new_meta = resp_body_json.meta

            assert.equal(new_meta, current_meta)
          end)
        end)
      end)

      describe("/credentials #test", function()
        local credential

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          consumer_approved = bp.consumers:insert {
            username = "hawk",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.APPROVED,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "hawk",
            password    = "kong",
            consumer_id = consumer_approved.id,
          })

          configure_portal(dao)
        end)

        before_each(function()
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("POST", function()
          it("adds a credential to a developer - basic-auth", function()
            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/credentials",
              body = {
                username = "kong",
                password = "hunter1"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)

            credential = resp_body_json

            assert.equal("kong", credential.username)
            assert.are_not.equals("hunter1", credential.password)
            assert.is_true(utils.is_valid_uuid(credential.id))
          end)
        end)

        describe("PATCH", function()
          it("patches a credential - basic-auth", function()
            local res = assert(portal_api_client:send {
              method = "PATCH",
              path = "/credentials",
              body = {
                id = credential.id,
                username = "anotherone",
                password = "another-hunter1"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local credential_res = resp_body_json

            assert.equal("anotherone", credential_res.username)
            assert.are_not.equals(credential_res.username, credential.username)
            assert.are_not.equals("another-hunter1", credential_res.password)
            assert.is_true(utils.is_valid_uuid(credential_res.id))
          end)
        end)
      end)

      describe("/credentials/:plugin ", function()
        local credential
        local credential_key_auth

        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            rbac       = rbac,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "on",
          }))

          consumer_approved = bp.consumers:insert {
            username = "hawk",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.APPROVED,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "hawk",
            password    = "kong",
            consumer_id = consumer_approved.id,
          })

          configure_portal(dao)
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            assert.res_status(404, res)
          end)

          it("adds auth plugin credential - basic-auth", function()
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(201, res)
            local resp_body_json = cjson.decode(body)

            credential = resp_body_json

            assert.equal("dude", credential.username)
            assert.are_not.equals("hunter1", credential.password)
            assert.is_true(utils.is_valid_uuid(credential.id))
          end)

          it("adds auth plugin credential - key-auth", function()
            local plugin = "key-auth"

            local res = assert(portal_api_client:send {
              method = "POST",
              path = "/credentials/" .. plugin,
              body = {
                key = "letmein"
              },
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
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
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            assert.res_status(404, res)
          end)

          it("retrieves a credential - basic-auth", function()
            local plugin = "basic-auth"
            local path = "/credentials/" .. plugin .. "/" .. credential.id

            local res = assert(portal_api_client:send {
              method = "GET",
              path = path,
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local credential_res = resp_body_json

            assert.equal(credential.username, credential_res.username)
            assert.equal(credential.id, credential_res.id)
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            assert.res_status(404, res)
          end)

          it("/credentials/:plugin/ - basic-auth", function()
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local credential_res = resp_body_json

            assert.equal("dudett", credential_res.username)
            assert.are_not.equals("a-new-password", credential_res.password)
            assert.is_true(utils.is_valid_uuid(credential_res.id))

            assert.are_not.equals(credential_res.username, credential.username)
          end)

          it("/credentials/:plugin/:credential_id - basic-auth", function()
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
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)
            local credential_res = resp_body_json

            assert.equal("duderino", credential_res.username)
            assert.are_not.equals("a-new-new-password", credential_res.password)
            assert.is_true(utils.is_valid_uuid(credential_res.id))

            assert.are_not.equals(credential_res.username, credential.username)
          end)
        end)

        describe("DELETE", function()
          it("deletes a credential", function()
            local plugin = "key-auth"
            local path = "/credentials/"
                          .. plugin .. "/" .. credential_key_auth.id

            local res = assert(portal_api_client:send {
              method = "DELETE",
              path = path,
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            assert.res_status(204, res)

            local res = assert(portal_api_client:send {
              method = "GET",
              path = path,
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            assert.res_status(404, res)
          end)
        end)

        describe("GET", function()
          it("retrieves the kong config tailored for the dev portal", function()
            local res = assert(portal_api_client:send {
              method = "GET",
              path = "/config",
              headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
              }
            })

            local body = assert.res_status(200, res)
            local resp_body_json = cjson.decode(body)

            local config = resp_body_json

            assert.same({}, config.plugins.enabled_in_cluster)
          end)
        end)
      end)

      describe("Vitals off ", function()
        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            vitals     = false,
            portal_auth = "basic-auth",
            rbac = rbac,
            portal_auth_config = "{ \"hide_credentials\": true }",
          }))

          consumer_approved = bp.consumers:insert {
            username = "hawk",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.APPROVED,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "hawk",
            password    = "kong",
            consumer_id = consumer_approved.id,
          })

          configure_portal(dao)
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("/vitals/status_codes/by_consumer", function()
          describe("GET", function()

            it("returns 404 when vitals if off", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
                },
              })

              assert.res_status(404, res)
            end)
          end)
        end)
      end)

      describe("Vitals on", function()
        setup(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            vitals     = true,
            portal_auth = "basic-auth",
            rbac = rbac,
            portal_auth_config = "{ \"hide_credentials\": true }",
          }))

          local consumer_pending = bp.consumers:insert {
            username = "dale",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.PENDING,
          }

          consumer_approved = bp.consumers:insert {
            username = "hawk",
            type = enums.CONSUMERS.TYPE.DEVELOPER,
            status = enums.CONSUMERS.STATUS.APPROVED,
          }

          assert(dao.basicauth_credentials:insert {
            username    = "dale",
            password    = "kong",
            consumer_id = consumer_pending.id,
          })

          assert(dao.basicauth_credentials:insert {
            username    = "hawk",
            password    = "kong",
            consumer_id = consumer_approved.id,
          })

          configure_portal(dao)
        end)

        before_each(function()
          client = assert(helpers.admin_client())
          portal_api_client = assert(ee_helpers.portal_api_client())
        end)

        after_each(function()
          if client then
            client:close()
          end

          if portal_api_client then
            portal_api_client:close()
          end
        end)

        describe("/vitals/status_codes/by_consumer", function()
          describe("GET", function()
            it("returns 401 when unauthenticated", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
              })

              assert.res_status(401, res)
            end)

            it("returns 401 when consumer is not approved", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)

              assert.same({ status = 1, label = "PENDING" }, json)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = consumer_approved.id,
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = consumer_approved.id,
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

            it("returns 401 when consumer is not approved", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)

              assert.same({ status = 1, label = "PENDING" }, json)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/status_codes/by_consumer_and_route",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = consumer_approved.id,
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
                },
              })

              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

              assert.same({
                meta = {
                  entity_id   = consumer_approved.id,
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

            it("returns 401 when consumer is not approved", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("dale:kong"),
                },
              })

              local body = assert.res_status(401, res)
              local json = cjson.decode(body)
              assert.same({ status = 1, label = "PENDING" }, json)
            end)

            it("returns 400 when requested with invalid interval query param", function()
              local res = assert(portal_api_client:send {
                method = "GET",
                path = "/vitals/consumers/cluster",
                query = {
                  interval = "derp",
                },
                headers = {
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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
                  ["Authorization"] = "Basic " .. ngx.encode_base64("hawk:kong"),
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

pending("portal dao_helpers", function()
  local dao

  setup(function()
    dao = select(3, helpers.get_db_utils("cassandra"))

    local cassandra = require "kong.dao.db.cassandra"
    local dao_cassandra = cassandra.new(helpers.test_conf)

    -- raw cassandra insert without dao so "type" is nil
    for i = 1, 10 do
      local query = string.format([[INSERT INTO %s.consumers
                                                (id, custom_id)
                                                VALUES(%s, '%s')]],
                                  helpers.test_conf.cassandra_keyspace,
                                  utils.uuid(),
                                  "cassy-" .. i)
      dao_cassandra:query(query)
    end

    local rows = dao.consumers:find_all()

    assert.equals(10, #rows)
    for _, row in ipairs(rows) do
      assert.is_nil(row.type)
    end

  end)

  teardown(function()
    helpers.stop_kong()
  end)

  it("updates consumers with nil type to default proxy type", function()
    local portal = require "kong.portal.dao_helpers"
    portal.update_consumers(dao, enums.CONSUMERS.TYPE.PROXY)

    local rows = dao.consumers:find_all()
    for _, row in ipairs(rows) do
      assert.equals(enums.CONSUMERS.TYPE.PROXY, row.type)
    end
    assert.equals(10, #rows)
  end)
end)
