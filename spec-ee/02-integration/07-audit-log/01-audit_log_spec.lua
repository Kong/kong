local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("audit_log with #" .. strategy, function()
    local admin_client, proxy_client
    local db, bp

    setup(function()
      bp, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1.5 or 0.5)
    end

    describe("audit requests", function()
      it("creates a single audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)
        local req_id = res.headers["X-Kong-Admin-Request-ID"]

        delay()

        res = assert(admin_client:send({
          path = "/audit/requests"
        }))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.data)
        assert.same(req_id, json.data[1].request_id)

        res = assert(admin_client:send({
          path = "/audit/requests"
        }))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(2, #json.data)
      end)

      it("creates an entry with the appropriate workspace association", function()
        local ws_foo = assert(bp.workspaces:insert({
          name = "foo",
        }))

        local res = assert(admin_client:send({
          path = "/foo/consumers",
        }))
        assert.res_status(200, res)

        delay()

        res = assert(admin_client:send({
          path = "/audit/requests"
        }))
        local json = cjson.decode(assert.res_status(200, res))

        assert.same(1, #json.data)
        assert.same(ws_foo.id, json.data[1].workspace)
      end)

      it("does not sign the audit log entry by default", function()
        local rows = db.audit_requests:select_all()
        for _, row in ipairs(rows) do
          assert.is_nil(row.signature)
        end
      end)

      it("creates an audit log entry when no workspace is found", function()
        local res = assert(admin_client:send({
          path = "/fdsfds/consumers",
        }))
        assert.res_status(404, res)
        local req_id = res.headers["X-Kong-Admin-Request-ID"]

        delay()

        res = assert(admin_client:send({
          path = "/audit/requests?request_id=" .. req_id
        }))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(1, #json.data)
        assert.same(ngx.null, json.data[1].workspace)
      end)

    end)

    describe("audit objects", function()
      describe("creates an audit log entry", function()
        describe("for object", function()
          it("CREATE", function()
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
  
            delay()
  
            local body = assert.res_status(200, admin_client:get("/audit/objects"))
            local json = cjson.decode(body)

            assert.same(4, #json.data)

            for _, object in ipairs(json.data) do
              assert.same("create", object.operation)
              if object.dao_name == "consumers" then
                assert.matches('"username":"bob"', object.entity, nil, true)
              end
            end
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

            delay()

            local body = assert.res_status(200, admin_client:get("/audit/objects"))
            local json = cjson.decode(body)

            assert.same(3, #json.data)

            for _, object in ipairs(json.data) do
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

            delay()

            local body = assert.res_status(200, admin_client:get("/audit/objects"))
            local json = cjson.decode(body)

            assert.same(4, #json.data)

            for _, object in ipairs(json.data) do
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
              path   = "/consumers",
              body   = {
                username = "c3"
              },
              headers = {
                ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(201, res)

            delay()

            local body = assert.res_status(200, admin_client:get("/audit/objects"))
            local json = cjson.decode(body)

            -- 1 row for the main entity, plus 3 in workspace_entities, one
            -- for each non-nil unique field, plus PK
            assert.same(4, #json.data)
            assert.same("create", json.data[1].operation)
            assert.same("create", json.data[2].operation)
            assert.same("create", json.data[3].operation)
            assert.same("create", json.data[4].operation)
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("for ignored methods", function()
      it("does not create an audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

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

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)

        assert.same(1, #json.data)
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
        audit_log_ignore_paths = "/consumers,/foo",
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("for an ignored path prefix", function()
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

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)

        assert.same(0, #json.data)
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

        delay()

        assert.same(1, #db.audit_requests:select_all())

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
        print(res)

        assert.same(1, #db.audit_requests:select_all())
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

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)

        assert.same(1, #json.data)
      end)
    end)

    describe("for an unrelated inferred workspace", function()
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

        delay()

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

        delay()

        -- 3 entries, 2 for the prevous 2 object creations
        -- and 1 for the workspace_association
        local body = assert.res_status(200, admin_client:get("/audit/objects"))
        local json = cjson.decode(body)

        assert.same(4, #json.data)

        for _, row in ipairs(json.data) do
          local f = {
            services = true,
            workspaces = true,
            workspace_entities = true
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

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

        delay()

        -- workspace_entities audit log entries
        local body = assert.res_status(200, admin_client:get("/audit/objects"))
        local json = cjson.decode(body)
        assert.same(3, #json.data)

        for _, row in ipairs(json.data) do
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

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/objects"))
        local json = cjson.decode(body)
        assert.same(3, #json.data)
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("generates records", function()
      it("expiring after their ttl", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)
        assert.same(1, #json.data)

        ngx.sleep(MOCK_TTL + 1)

        res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        body = assert.res_status(200, admin_client:get("/audit/requests"))
        json = cjson.decode(body)
        assert.same(1, #json.data)
      end)
    end)
  end)

  describe("audit_log signing_key with #" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      os.execute("openssl genrsa -out ./spec/fixtures/key.pem 2048 2>/dev/null")

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_signing_key = "./spec/fixtures/key.pem",
      }))
    end)

    teardown(function()
      helpers.stop_kong(nil, true)

      os.execute("rm -f ./spec/fixtures/key.pem")
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("audit log entries", function()
      it("are generated with an adjacent signature", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        local body = assert.res_status(200, admin_client:get("/audit/requests"))
        local json = cjson.decode(body)
        assert.same(1, #json.data)

        assert.not_nil(json.data[1].signature)
      end)
    end)
  end)

  -- This test is for cases when ngx.ctx.workspaces is not set correctly
  -- when serving requests like "GET /userinfo" or "GET /default/kong".
  describe("audit_log with rbac and admin_gui_auth" .. strategy, function()
    local db, admin_client, proxy_client

    setup(function()
      db = select(2, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        admin_gui_auth = "basic-auth",
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

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("audit log", function()
      it("creates an audit_request entry", function()
        local res = assert(admin_client:send({
          path = "/default/kong",
        }))
        assert.res_status(401, res)

        delay()

        assert.same(1, #db.audit_requests:select_all())
      end)
    end)
  end)
end
