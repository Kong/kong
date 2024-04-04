-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local cjson = require "cjson"

local function insert_dummy_audit_request(bp, id, timestamp)
  return bp.audit_requests:insert({
    request_id = id,
    path = "/services",
    request_timestamp = timestamp,
  })
end

for _, strategy in helpers.each_strategy() do
  describe("audit_log API with #" .. strategy, function()
    local admin_client
    local bp
    local db

    setup(function()
      bp, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_paths = [[/audit/requests(\?.+)?]],
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      db:truncate("audit_requests")
      db:truncate("audit_objects")
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      admin_client:close()
    end)

    describe("audit requests", function()
      before_each(function()
        insert_dummy_audit_request(bp, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", os.time({year = 2024, month = 3, day = 12}))
        insert_dummy_audit_request(bp, "dddddddddddddddddddddddddddddddd", os.time({year = 2024, month = 3, day = 11}))
        insert_dummy_audit_request(bp, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", os.time({year = 2024, month = 3, day = 10}))
        insert_dummy_audit_request(bp, "ffffffffffffffffffffffffffffffff", os.time({year = 2024, month = 3, day = 10}))
        insert_dummy_audit_request(bp, "cccccccccccccccccccccccccccccccc", os.time({year = 2024, month = 3, day = 9}))
        insert_dummy_audit_request(bp, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", os.time({year = 2024, month = 3, day = 8}))
      end)

      it("registers calls to API", function()
        local res, json
        local initial_audit_log_size = 6

        res = assert.res_status(200, admin_client:send({path = "/audit/requests"}))
        json = cjson.decode(res)
        assert.same(initial_audit_log_size, #json.data) -- some audit logs are already present

        -- make additional calls
        assert.res_status(200, admin_client:get("/services"))
        assert.res_status(200, admin_client:get("/services"))
        assert.res_status(200, admin_client:get("/services"))

        -- expect to have 3 additional audit logs
        res = assert.res_status(200, admin_client:send({path = "/audit/requests"}))
        json = cjson.decode(res)
        assert.same(initial_audit_log_size + 3, #json.data)
      end)

      -- Assert paging behavior - given we have custom logic for paging in
      -- audit endpoints
      it("returns paged results sorted by request_timestamp descending", function()
        local res, json

        res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {size = 2}
        }))
        json = cjson.decode(res)
        assert.same(2, #json.data)

        assert.matches("^/audit/requests", json.next)
        assert.same("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", json.data[1].request_id)
        assert.same("dddddddddddddddddddddddddddddddd", json.data[2].request_id)

        local offset = json.offset
        res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {size = 2, offset = offset}
        }))
        json = cjson.decode(res)
        assert.same(2, #json.data)
        -- with the same timestamp - sorted by request_id (also descending)
        assert.same("ffffffffffffffffffffffffffffffff", json.data[1].request_id)
        assert.same("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", json.data[2].request_id)

        offset = json.offset
        res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {size = 2, offset = offset}
        }))
        json = cjson.decode(res)
        assert.same(2, #json.data)
        assert.same("cccccccccccccccccccccccccccccccc", json.data[1].request_id)
        assert.same("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", json.data[2].request_id)
      end)

      it("returns results sorted by other column if requested - only sort_by passed", function()
        local res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {sort_by = "request_id"}
        }))
        local json = cjson.decode(res)
        assert.same(6, #json.data)

        assert.same("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", json.data[1].request_id)
        assert.same("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", json.data[2].request_id)
        assert.same("cccccccccccccccccccccccccccccccc", json.data[3].request_id)
        assert.same("dddddddddddddddddddddddddddddddd", json.data[4].request_id)
        assert.same("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", json.data[5].request_id)
        assert.same("ffffffffffffffffffffffffffffffff", json.data[6].request_id)
      end)

      it("returns results sorted by other column if requested - both sort_by and sort_desc passed", function()
        local res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {sort_by = "request_id", sort_desc = false}
        }))
        local json = cjson.decode(res)
        assert.same(6, #json.data)

        assert.same("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", json.data[1].request_id)
        assert.same("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", json.data[2].request_id)
        assert.same("cccccccccccccccccccccccccccccccc", json.data[3].request_id)
        assert.same("dddddddddddddddddddddddddddddddd", json.data[4].request_id)
        assert.same("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", json.data[5].request_id)
        assert.same("ffffffffffffffffffffffffffffffff", json.data[6].request_id)
      end)

      it("returns results in custom order if requested", function()
        local res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {sort_by = "request_id", sort_desc = true}
        }))
        local json = cjson.decode(res)
        assert.same(6, #json.data)

        assert.same("ffffffffffffffffffffffffffffffff", json.data[1].request_id)
        assert.same("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", json.data[2].request_id)
        assert.same("dddddddddddddddddddddddddddddddd", json.data[3].request_id)
        assert.same("cccccccccccccccccccccccccccccccc", json.data[4].request_id)
        assert.same("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", json.data[5].request_id)
        assert.same("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", json.data[6].request_id)
      end)
    end)

    describe("audit objects", function()
      -- Assert paging behavior - given we have custom logic for paging in
      -- audit endpoints
      it("returns paged results", function()
        assert.res_status(201, admin_client:post("/consumers", {
          body = {
            username = "c1"
          },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, admin_client:post("/consumers", {
          body = {
            username = "c2"
          },
          headers = {["Content-Type"] = "application/json"}
        }))
        assert.res_status(201, admin_client:post("/consumers", {
          body = {
            username = "c3"
          },
          headers = {["Content-Type"] = "application/json"}
        }))

        local res, json

        --[[
          The function `admin_log_handler` is called in `log_by_lua_block`.
          In this phase, the request is done, so we can receive the reponse,
          but this function may be not be called now.
        --]]
        helpers.pwait_until(function ()
          res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {size = 2}
          }))
          json = cjson.decode(res)
          assert.same(2, #json.data)

          assert.matches("^/audit/objects", json.next)

          res = assert.res_status(200, admin_client:send({
            path = "/audit/objects",
            query = {size = 2, offset = json.offset}
          }))
          json = cjson.decode(res)
          assert.same(1, #json.data)
        end)

      end)
    end)
  end)

  describe("audit_log API with RBAC #" .. strategy, function()
    local admin_client
    local db

    before_each(function()
      _, db = helpers.get_db_utils(strategy)

      local conf = {
        database = strategy,
        admin_gui_url = "http://manager.konghq.com",
        admin_gui_auth = 'basic-auth',
        audit_log = "on",
        admin_gui_session_conf = "{ \"secret\": \"super-secret\" }",
        admin_gui_auth_password_complexity = "{\"kong-preset\": \"min_12\"}",
        enforce_rbac = "on",
        password = "foo",
        prefix = helpers.test_conf.prefix,
      }

      assert(helpers.kong_exec("migrations reset --yes", conf))
      assert(helpers.kong_exec("migrations bootstrap", conf))

      assert(helpers.start_kong(conf))

      ee_helpers.register_rbac_resources(db)
      admin_client = assert(helpers.admin_client())
    end)

    after_each(function()
      if admin_client then admin_client:close() end
      assert(helpers.stop_kong(nil, true))
    end)

    it("audit request should be have request-source and rbac_user_name", function()
      local options = {
        headers = {
          ["X-Request-Source"] = "Kong-Manager",
          ["Kong-Admin-User"]  = "kong_admin",
          ["Kong-Admin-Token"] = "foo"
        }
      }
      assert.res_status(200, admin_client:get("/services", options))
      assert.res_status(200, admin_client:get("/services", options))
      assert.res_status(200, admin_client:get("/services", options))

      local res, json

      res = assert.res_status(200, admin_client:send({
        path = "/audit/requests",
        query = { size = 2 },
        headers = options.headers
      }))
      json = cjson.decode(res)
      assert.same(2, #json.data)
      for key, value in pairs(json.data) do
        if key == "request-source" then
          assert.same("Kong-Manager", value)
        end
        if key == "rbac_user_name" then
          assert.same("kong_admin", value)
        end
      end

    end)
  end)
end
