local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do
  describe("audit_log with #" .. strategy, function()
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

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
    end)

    after_each(function()
      admin_client:close()
      proxy_client:close()
    end)

    local function delay()
      ngx.sleep(strategy == "cassandra" and 1 or 0.3)
    end

    describe("audit requests", function()
      local req_id, ws_foo

      it("creates a single audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)
        req_id = res.headers["X-Kong-Admin-Request-ID"]

        delay()

        assert.same(1, dao.audit_requests:count())

        res = assert(admin_client:send({
          path = "/audit/requests"
        }))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        delay()

        assert.same(req_id, json.data[1].request_id)
      end)

      it("creates a second log entry for the audit endpoint request", function()
        assert.same(2, dao.audit_requests:count())
      end)

      it("creates an entry with the appropriate workspace association", function()
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
        local body = assert.res_status(201, res)
        ws_foo = cjson.decode(body)

        res = assert(admin_client:send({
          path = "/foo/consumers",
        }))
        assert.res_status(200, res)
        req_id = res.headers["X-Kong-Admin-Request-ID"]

        delay()

        res = assert(admin_client:send({
          path = "/audit/requests?request_id=" .. req_id
        }))
        body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.same(ws_foo.id, json.data[1].workspace)
      end)

      it("does not sign the audit log entry by default", function()
        local rows = dao.audit_requests:find_all()
        for _, row in ipairs(rows) do
          assert.is_nil(row.signature)
        end
      end)

      it("creates an audit log entry when no workspace is found", function()
        local res = assert(admin_client:send({
          path = "/fdsfds/consumers",
        }))
        assert.res_status(404, res)
        req_id = res.headers["X-Kong-Admin-Request-ID"]

        delay()

        res = assert(admin_client:send({
          path = "/audit/requests?request_id=" .. req_id
        }))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)

        assert.is_nil(json.data[1].workspace)
      end)

    end)

    -- XXX EE: flaky
    pending("audit objects", function()
      describe("creates an audit log entry", function()
        describe("for object", function()
          local id

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
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            id = json.id
  
            delay()
  
            local rows = dao.audit_objects:find_all({
              request_id = res.headers["X-Kong-Admin-Request-ID"],
              dao_name   = "consumers",
            })
            assert.same(1, #rows)
            assert.same("create", rows[1].operation)
            assert.matches('"username":"bob"', rows[1].entity, nil, true)
          end)

          it("UPDATE", function()
            local res = assert(admin_client:send({
              method = "PATCH",
              path   = "/consumers/" .. id,
              body   = {
                username = "fred"
              },
              headers = {
              ["Content-Type"] = "application/json",
              }
            }))
            assert.res_status(200, res)

            delay()

            local rows = dao.audit_objects:find_all({
              request_id = res.headers["X-Kong-Admin-Request-ID"],
              dao_name   = "consumers",
            })
            assert.same(1, #rows)
            assert.same("update", rows[1].operation)
            assert.matches('"username":"fred"', rows[1].entity, nil, true)
          end)

          it("DELETE", function()
            local res = assert(admin_client:send({
              method = "DELETE",
              path   = "/consumers/" .. id,
            }))
            assert.res_status(204, res)

            delay()

            local rows = dao.audit_objects:find_all({
              request_id = res.headers["X-Kong-Admin-Request-ID"],
              dao_name   = "consumers",
            })
            assert.same(1, #rows)
            assert.same("delete", rows[1].operation)
            assert.matches('"username":"fred"', rows[1].entity, nil, true)
          end)
        end)

        describe("for workspace associations", function()
          it("", function()
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
  
            local rows = dao.audit_objects:find_all({
              request_id = res.headers["X-Kong-Admin-Request-ID"],
              dao_name   = "workspace_entities",
            })
            assert.same(2, #rows)
            assert.same("create", rows[1].operation)
            assert.same("create", rows[2].operation)
          end)
        end)
      end)
    end)
  end)

  describe("audit_log ignore_methods with #" .. strategy, function()
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_methods = "GET",
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
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

    describe("for ignored methods", function()
      it("does not create an audit log entry", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        assert.same(0, dao.audit_requests:count())
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

        assert.same(1, dao.audit_requests:count())
      end)
    end)
  end)

  describe("audit_log ignore_paths with #" .. strategy, function()
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_paths = "/consumers,/foo",
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
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

        assert.same(0, dao.audit_requests:count())
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

        assert.same(1, dao.audit_requests:count())

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

        delay()

        assert.same(1, dao.audit_requests:count())
      end)
    end)

    describe("for an unrelated path", function()
      setup(function()
        dao.audit_requests:truncate()
        dao.audit_objects:truncate()
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

        assert.same(1, dao.audit_requests:count())
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
        assert.same(3, dao.audit_requests:count())

        local rows = dao.audit_objects:find_all()
        for _, row in ipairs(rows) do
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
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_tables = "consumers",
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
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
        assert.same(2, dao.audit_objects:count())
        local rows = dao.audit_objects:find_all()
        for _, row in ipairs(rows) do
          assert.not_same(row.dao_name, "consumers")
        end
      end)
    end)

    describe("for an unrelated table", function()
      setup(function()
        dao.audit_requests:truncate()
        dao.audit_objects:truncate()
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

        assert.same(1, dao.audit_requests:count())
      end)
    end)
  end)

  describe("audit_log record_ttl with #" .. strategy, function()
    local dao, admin_client, proxy_client
    local MOCK_TTL = 2

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_record_ttl = MOCK_TTL,
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
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

    describe("generates records", function()
      it("expiring after their ttl", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        assert.same(1, dao.audit_requests:count())

        ngx.sleep(MOCK_TTL + 1)

        res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        assert.same(1, dao.audit_requests:count())
      end)
    end)
  end)

  describe("audit_log signing_key with #" .. strategy, function()
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      os.execute("openssl genrsa -out ./spec/fixtures/key.pem 2048 2>/dev/null")

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_signing_key = "./spec/fixtures/key.pem",
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
    end)

    teardown(function()
      helpers.stop_kong(nil, true)

      os.execute("rm -f ./spec/fixtures/key.pem")
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

    describe("audit log entries", function()
      it("are generated with an adjacent signature", function()
        local res = assert(admin_client:send({
          path = "/",
        }))
        assert.res_status(200, res)

        delay()

        assert.same(1, dao.audit_requests:count())

        local entry = dao.audit_requests:find_all()[1]
        assert.not_nil(entry.signature)
      end)
    end)
  end)

  -- This test is for cases when ngx.ctx.workspaces is not set correctly
  -- when serving requests like "GET /userinfo" or "GET /default/kong".
  describe("audit_log with rbac and admin_gui_auth" .. strategy, function()
    local dao, admin_client, proxy_client

    setup(function()
      dao = select(3, helpers.get_db_utils(strategy))

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        admin_gui_auth = "basic-auth",
        enforce_rbac = "on",
        admin_gui_listen = "0.0.0.0:8002",
      }))

      dao.audit_requests:truncate()
      dao.audit_objects:truncate()
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

    describe("audit log", function()
      it("creates an audit_request entry", function()
        local res = assert(admin_client:send({
          path = "/default/kong",
        }))
        assert.res_status(401, res)

        delay()

        assert.same(1, dao.audit_requests:count())
      end)
    end)
  end)
end
