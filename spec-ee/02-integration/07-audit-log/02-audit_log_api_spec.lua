local helpers = require "spec.helpers"
local cjson = require "cjson"


for _, strategy in helpers.each_strategy() do
  describe("audit_log API with #" .. strategy, function()
    local admin_client

    setup(function()
      helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        audit_log  = "on",
        audit_log_ignore_paths = "/audit/requests",
        audit_log_ignore_tables = "workspace_entities",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      admin_client = helpers.admin_client()
    end)

    after_each(function()
      admin_client:close()
    end)

    describe("audit requests", function()
      -- Assert paging behavior - given we have custom logic for paging in
      -- audit endpoints
      it("#flaky returns paged results", function()
        assert.res_status(200, admin_client:get("/services"))
        assert.res_status(200, admin_client:get("/services"))
        assert.res_status(200, admin_client:get("/services"))

        local res, json

        res = assert.res_status(200, admin_client:send({
          path = "/audit/requests",
          query = {size = 2}
        }))
        json = cjson.decode(res)
        assert.same(2, #json.data)

        assert.matches("^/audit/requests", json.next)

        local offset = json.offset
        helpers.wait_until(function()
          ngx.sleep(1)
          res = assert.res_status(200, admin_client:send({
            path = "/audit/requests",
            query = {size = 2, offset = offset}
          }))
          json = cjson.decode(res)
          return 1 == #json.data
        end, 10)
        assert.same(1, #json.data)

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
end
