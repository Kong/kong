-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local admin_api = require "spec.fixtures.admin_api"
local pl_file = require "pl.file"

local fmt = string.format
local TEST_CONF = helpers.test_conf

local function fetch_all(dao)
  local rows = {}
  for row in dao:each() do
    table.insert(rows, row)
  end
  return rows
end

local function find_in_file(pat)
  local f = assert(io.open(TEST_CONF.prefix .. "/" .. TEST_CONF.proxy_error_log, "r"))
  local line = f:read("*l")

  while line do
    if line:match(pat) then
      return true
    end

    line = f:read("*l")
  end

  return false
end


for _, strategy in helpers.each_strategy() do
  describe("audit_log with #" .. strategy, function()
    local admin_client, proxy_client
    local db, bp

    lazy_setup(function()
      local fixtures = {
        http_mock = {
          audit_server = [[
            server {
                server_name example.com;
                listen 16798;

                location = / {
                    content_by_lua_block {
                        local get_request_id = require("kong.tracing.request_id").get
                        ngx.say(get_request_id())
                    }
                }
            }
          ]],
        },
      }

      bp, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
      }, nil, nil, fixtures))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db:truncate("audit_objects")
      db:truncate("audit_requests")
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("get_request_id()", function()
      it("should never return empty outside the context of Admin API request", function()
        local client = helpers.proxy_client(nil, 16798, "127.0.0.1")
        local res = client:send {
          method = "GET",
          path = "/",
          headers = {
            ["Host"] = "example.com",
          }
        }
        local body = assert.res_status(200, res)
        assert.truthy(#body == 32)
      end)
    end)

    describe("audit requests", function()
      it("creates a single audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)
        local req_id = res.headers["X-Kong-Admin-Request-ID"]

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 1 and req_id == rows[1].request_id
        end)
      end)

      it("creates an entry with the appropriate workspace association", function()
        local ws_foo = assert(bp.workspaces:insert({
          name = "foo",
        }))

        local res = assert(admin_client:send({
          path = "/foo/services",
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 1 and ws_foo.id == rows[1].workspace
        end)
      end)

      it("checks if request_timestamp is a number", function()
        local res = assert(admin_client:send({
          path = "/services",
        }))
        assert.res_status(200, res)
        local req_id = res.headers["X-Kong-Admin-Request-ID"]

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 1 and req_id == rows[1].request_id
                            and type(rows[1].request_timestamp) == "number"
        end)
      end)

      it("checks if timestamp returned is correct", function()
        local audit_request_record = {
          request_id = "request-test-id",
          request_timestamp = 1582659601,
          client_ip = "127.0.0.1",
          path = "/services",
          method = "GET",
          status = 200,
        }
        helpers.wait_until(function()
          return db.audit_requests:insert(audit_request_record)
        end)

        local res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {size = 2}
        }))
        local json = cjson.decode(res)
        assert.same(audit_request_record.request_timestamp, json.data[1].request_timestamp)
      end)

      it("does not sign the audit log entry by default", function()
        local rows = fetch_all(db.audit_requests)
        for _, row in ipairs(rows) do
          assert.is_nil(row.signature)
        end
      end)

      it("creates an audit log entry when no workspace is found", function()
        local res = assert(admin_client:send({
          path = "/fdsfds/consumers",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 1 and rows[1].workspace == nil
        end)
      end)

    end)

    describe("audit objects", function()
      describe("creates an audit log entry", function()
        describe("for object", function()
          it("CREATE", function()
            local res = assert(admin_client:send({
              method = "POST",
              path   = "/services",
              body   = {
                name = "bob",
                host = "example.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            }))
            local service = cjson.decode(assert.res_status(201, res))

            local rows

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 1
            end)

            for _, object in ipairs(rows) do
              assert.same("create", object.operation)
              if object.dao_name == "services" then
                assert.matches('"name":"bob"', object.entity, nil, true)
              end
            end

            res = assert(admin_client:send({
              method = "POST",
              path   = "/rbac/roles",
              body   = {
                name = "role123"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(201, res)

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 2
            end)

            res = assert(admin_client:send({
              method = "POST",
              path   = "/rbac/roles/role123/entities",
              body   = {
                entity_id = service.id,
                entity_type = "services",
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(201, res)

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 3
            end)
          end)

          it("CREATE on proxy side", function()
            -- oauth2 plugin creates entities on the proxy side; use it to assert
            -- that audit log creates an object log on the proxy path

            assert(admin_api.routes:insert({
              paths     = { "/" },
            }))
            local c1 = admin_api.consumers:insert({
              username = "consumer123",
              custom_id = "consumer123"
            })
            local client1 = admin_api.oauth2_credentials:insert {
              client_id      = "clientid123",
              client_secret  = "secret123",
              redirect_uris  = { "http://google.com/kong" },
              name           = "testapp",
              consumer       = { id = c1.id },
            }
            local plugin = admin_api.oauth2_plugins:insert({
              config   = {
                enable_authorization_code = true,
                scopes = { "email", "profile", "user.email" },
              },
            })

            helpers.wait_until(function()
              local proxy_ssl_client = helpers.proxy_ssl_client()
              local res = assert(proxy_ssl_client:send {
                method  = "POST",
                path    = "/oauth2/authorize",
                body    = {
                  provision_key = plugin.config.provision_key,
                  client_id = client1.client_id,
                  authenticated_userid = "userid123",
                  scope = "email",
                  response_type = "code",
                  state = "hello"
                },
                headers = {
                  ["Content-Type"] = "application/json"
                }
              })
              proxy_ssl_client:close()
              return res.status == 200
            end)

            helpers.wait_until(function()
              local rows = fetch_all(db.audit_objects)
              local found = false
              for _, entry in ipairs(rows) do
                if entry.dao_name == "oauth2_authorization_codes" then
                  found = true
                end
              end
              return found == true
            end)
          end)

          it("UPDATE", function()
            -- note: as object audit log events are inserted from worker events,
            -- entities inserted directly from the dao are not accounted for
            local c1 = bp.consumers:insert({
              username = "c1",
            })

            local res = assert(admin_client:patch("/consumers/" .. c1.id, {
              body   = {
                username = "c2"
              },
              headers = {
              ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(200, res)

            local rows

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 1
            end)

            for _, object in ipairs(rows) do
              assert.same("update", object.operation)
              if object.dao_name == "consumers" then
                assert.matches('"username":"c2"', object.entity, nil, true)
              end
            end
          end)

          it("DELETE", function()
            local c1 = bp.consumers:insert({
              username = "fred",
            })

            local res = assert(admin_client:send({
              method = "DELETE",
              path   = "/consumers/" .. c1.id,
            }))
            assert.res_status(204, res)

            local rows

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 1
            end)

            for _, object in ipairs(rows) do
              assert.same("delete", object.operation)
              if object.dao_name == "consumers" then
                assert.matches('"username":"fred"', object.entity, nil, true)
              end
            end
          end)
        end)

        describe("for workspace associations", function()
          it("", function()
            local res = assert(admin_client:send({
              method = "POST",
              path   = "/services",
              body   = {
                name = "s2",
                host = "foo.com"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(201, res)

            local rows

            helpers.wait_until(function()
              rows = fetch_all(db.audit_objects)
              return #rows == 1
            end)

            assert.same("create", rows[1].operation)
          end)
        end)
      end)
    end)
  end)

  describe("audit_log ignore_methods with #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_methods = "GET",
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db:truncate("audit_objects")
      db:truncate("audit_requests")
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("for ignored methods", function()
      it("does not create an audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        ngx.sleep(2)

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)

        assert.same(0, #json.data)
      end)
    end)

    describe("for unrelated methods", function()
      it("generates an audit log entry", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/consumers",
          body   = {
            username = "bob"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 1
        end)
      end)
    end)
  end)

  describe("audit_log ignore_paths with #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_paths = "/consumers,/foo,^/status,/routes$," ..
                                 "/one/.+/two,/[bad-regex,/.*/plugins"
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db:truncate("audit_objects")
      db:truncate("audit_requests")
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("for an ignored path prefix", function()
      -- XXX flaky: only happens on CI
      it("does not generate an audit log entry #flaky", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/consumers",
          body   = {
            username = "bob"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        ngx.sleep(2)

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)

        assert.same(0, #json.data)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/status",
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 0
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/routes",
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return #rows == 0
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/service/status/routes",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 0 == #rows
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/one/status/two",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 0 == #rows
        end)

        -- error log corresponding to the regex '/[bad-regex'
        assert(find_in_file("could not evaluate the regex"))
      end)
    end)

    describe("for an ignored workspace path prefix", function()
      it("does not generate an audit log entry", function()
        local res = assert(admin_client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "foo",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows
        end)

        res = assert(admin_client:send({
          method = "POST",
          path   = "/foo/services",
          body   = {
            name = "test",
            host = "example.com",
          },
          headers = {
            ["content-type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          return 1 == #fetch_all(db.audit_requests)
        end)

        res = assert(admin_client:send({
          method = "GET",
          path   = "/foo/plugins",
          body   = {
            name = "test",
            host = "example.com",
          },
          headers = {
            ["content-type"] = "application/json",
          }
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          return 1 == #fetch_all(db.audit_requests)
        end)
      end)
    end)

    describe("for an unrelated path", function()
      setup(function()
        db.audit_requests:truncate()
        db.audit_objects:truncate()
      end)

      it("generates an audit log entry", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/services",
          body   = {
            name = "test",
            host = "example.com",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/bad-actor-request/status",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/routes/test",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows
        end)

        db:truncate("audit_objects")
        db:truncate("audit_requests")

        res = assert(admin_client:send({
            method = "GET",
            path   = "/one/two",
        }))
        assert.res_status(404, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows
        end)

        -- error log corresponding to the regex '/[bad-regex'
        assert(find_in_file("could not evaluate the regex"))
      end)
    end)

    describe("for an unrelated inferred workspace #flaky", function()
      it("", function()
        local res = assert(admin_client:send {
          method = "POST",
          path   = "/workspaces",
          body   = {
            name = "bar",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        res = assert(admin_client:send {
          method = "POST",
          path   = "/bar/services",
          body   = {
            name = "test2",
            host = "example2.com",
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(201, res)

        local rows
        helpers.wait_until(function()
          rows = fetch_all(db.audit_objects)
          return #rows == 2
        end)

        for _, row in ipairs(rows) do
          local f = {
            services = true,
            workspaces = true,
          }

          assert.is_true(f[row.dao_name])
        end
      end)
    end)
  end)

  describe("audit_log ignore_tables with #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_tables = "consumers",
      }))

      db:truncate("audit_objects")
      db:truncate("audit_requests")
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("for an ignored table", function()
      it("does not generate an audit log entry", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/consumers",
          body   = {
            username = "bob"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)


        local rows
        helpers.wait_until(function()
          rows = fetch_all(db.audit_objects)
          return #rows == 0
        end)

        for _, row in ipairs(rows) do
          assert.not_same(row.dao_name, "consumers")
        end
      end)
    end)

    describe("for an unrelated table", function()
      setup(function()
        db.audit_requests:truncate()
        db.audit_objects:truncate()
      end)

      it("generates a log entry", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/services",
          body   = {
            name = "test",
            host = "example.com",
          },
          headers = {
            ["content-type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        helpers.wait_until(function()
          return #fetch_all(db.audit_objects) == 1
        end)
      end)
    end)
  end)

  describe("audit_log record_ttl with #" .. strategy, function()
    local db, admin_client, proxy_client
    local MOCK_TTL = 2

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_record_ttl = MOCK_TTL,
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db.audit_requests:truncate()
      db.audit_objects:truncate()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("generates records", function()
      it("expiring after their ttl", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          return 1 == #fetch_all(db.audit_requests)
        end)

        ngx.sleep(MOCK_TTL + 1)

        helpers.wait_until(function()
          return 0 == #fetch_all(db.audit_requests)
        end)
      end)
    end)
  end)

  describe("audit_log signing_key with #" .. strategy, function()
    local db, admin_client, proxy_client
    local key_file = "./spec/fixtures/key.pem"

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      os.execute(fmt("rm -f %s", key_file))
      os.execute(fmt("openssl genrsa -out %s 2048 2>/dev/null", key_file))
      os.execute(fmt("chmod 0777 %s", key_file))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_signing_key = key_file,
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)

      pl_file.delete(key_file)

    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db.audit_requests:truncate()
      db.audit_objects:truncate()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("audit log entries", function()
      it("are generated with an adjacent signature", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        helpers.wait_until(function()
          local rows = fetch_all(db.audit_requests)
          return 1 == #rows and rows[1].signature
        end)
      end)
    end)
  end)

  -- This test is for cases when ngx.ctx.workspace is not set correctly
  -- when serving requests like "GET /userinfo" or "GET /default/kong".
  describe("audit_log with rbac and admin_gui_auth #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database = strategy,
      }))
      admin_client = assert(helpers.admin_client())
      local res = assert(admin_client:send({
        method  = "POST",
        path    = "/default/rbac/users",
        body    = {
          name = "admin",
          user_token = "test_admin"
        },
        headers = {
          ["Content-Type"] = "application/json",
        }
      }))
      assert.res_status(201, res)
      
      helpers.stop_kong()
      
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        admin_gui_auth = "basic-auth",
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
        enforce_rbac = "on",
        admin_gui_listen = "0.0.0.0:8002",
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()

      db.audit_requests:truncate()
      db.audit_objects:truncate()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("audit log", function()
      it("creates an audit_request entry", function()
        local res = assert(admin_client:send({
          path = "/default/kong",
        }))
        assert.res_status(401, res)

        helpers.wait_until(function()
          return #fetch_all(db.audit_requests) == 1
        end)
      end)
      
      it("creates an audit_request entry with rbac token", function()
        local res = assert(admin_client:send({
          path = "/default/kong",
          headers = { ["Kong-Admin-Token"] = "test_admin" }
        }))
        assert.res_status(403, res)
        helpers.wait_until(function()
          return #fetch_all(db.audit_requests) == 1
        end)
      end)

    end)
  end)

  describe("audit_log audit_log_payload_exclude with #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_payload_exclude = "password",
      }))

      db:truncate("audit_objects")
      db:truncate("audit_requests")
    end)

    teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      admin_client = helpers.admin_client()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    describe("for an excluded key", function()
      it("does not include value in the payload", function()
        local res = assert(admin_client:send({
          method = "POST",
          path   = "/consumers",
          body   = {
            username = "bob"
          },
          headers = {
            ["Content-Type"] = "application/json",
          }
        }))
        assert.res_status(201, res)

        local res = assert(admin_client:send {
          method  = "POST",
          path    = "/consumers/bob/basic-auth",
          body    = {
            username = "bob",
            password = "kong"
          },
          headers = {
            ["Content-Type"] = "application/json"
          }
        })
        assert.res_status(201, res)


        local rows
        helpers.wait_until(function()
          rows = fetch_all(db.audit_requests)
          return #rows == 2
        end)

        for _, row in ipairs(rows) do
          if(row.path == "/consumers/bob/basic-auth") then
            assert.same("{\"username\":\"bob\"}", row.payload)
            assert.same("password", row.removed_from_payload)
          end
        end
      end)
    end)
  end)
end
