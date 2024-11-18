local helpers = require "spec.helpers"
local cjson = require("cjson.safe")

for _, strategy in helpers.each_strategy() do

describe("Incremental Sync RPC #" .. strategy, function()

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "clustering_data_planes",
    }) -- runs migrations

    assert(helpers.start_kong({
      role = "control_plane",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      database = strategy,
      cluster_listen = "127.0.0.1:9005",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      cluster_incremental_sync = "on", -- incremental sync
    }))

    assert(helpers.start_kong({
      role = "data_plane",
      database = "off",
      prefix = "servroot2",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      nginx_worker_processes = 4, -- multiple workers
      cluster_incremental_sync = "on", -- incremental sync
      worker_state_update_frequency = 1,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot2")
    helpers.stop_kong()
  end)

  after_each(function()
    helpers.clean_logfile("servroot2/logs/error.log")
    helpers.clean_logfile()
  end)

  describe("sync works", function()
    local route_id

    it("create route on CP", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-001", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-001/routes", {
        body = { paths = { "/001" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      route_id = json.id
      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/001",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)

      -- dp lua-resty-events should work without privileged_agent
      assert.logfile("servroot2/logs/error.log").has.line(
        "lua-resty-events enable_privileged_agent is false", true)
    end)

    it("update route on CP", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-002", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-002/routes", {
        body = { paths = { "/002-foo" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      route_id = json.id
      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/002-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      res = assert(admin_client:put("/services/service-002/routes/" .. route_id, {
        body = { paths = { "/002-bar" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/002-bar",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)
    end)

    it("delete route on CP", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-003", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-003/routes", {
        body = { paths = { "/003-foo" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      route_id = json.id
      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/003-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)
      assert.logfile("servroot2/logs/error.log").has.no.line("[kong.sync.v2] delete entity", true)

      res = assert(admin_client:delete("/services/service-003/routes/" .. route_id))
      assert.res_status(204, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/003-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 404 then
          return true
        end
      end, 10)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] delete entity", true)
    end)

    it("update route on CP with name", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-004", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-004/routes", {
        body = { name = "route-004", paths = { "/004-foo" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/004-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      res = assert(admin_client:put("/services/service-004/routes/route-004", {
        body = { paths = { "/004-bar" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(200, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/004-bar",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)
    end)

    it("delete route on CP with name", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-005", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-005/routes", {
        body = { name = "route-005", paths = { "/005-foo" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/005-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)
      assert.logfile("servroot2/logs/error.log").has.no.line("[kong.sync.v2] delete entity", true)

      res = assert(admin_client:delete("/services/service-005/routes/route-005"))
      assert.res_status(204, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/005-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 404 then
          return true
        end
      end, 10)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] delete entity", true)
    end)

    it("cascade delete on CP", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      -- create service and route

      local res = assert(admin_client:post("/services", {
        body = { name = "service-006", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/services/service-006/routes", {
        body = { paths = { "/006-foo" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)

      route_id = json.id
      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/006-foo",
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] config push (connected client)", true)
      assert.logfile().has.no.line("unable to update clustering data plane status", true)

      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)

      -- create consumer and key-auth

      res = assert(admin_client:post("/consumers", {
        body = { username = "foo", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      res = assert(admin_client:post("/consumers/foo/key-auth", {
        body = { key = "my-key", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)
      res = assert(admin_client:post("/plugins", {
        body = { name = "key-auth",
                 config = { key_names = {"apikey"} },
                 route = { id = route_id },
               },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/006-foo",
          headers = {["apikey"] = "my-key"},
        })

        local status = res and res.status
        proxy_client:close()
        if status == 200 then
          return true
        end
      end, 10)

      assert.logfile().has.no.line("[kong.sync.v2] new delta due to cascade deleting", true)
      assert.logfile("servroot2/logs/error.log").has.no.line("[kong.sync.v2] delete entity", true)

      -- delete consumer and key-auth

      res = assert(admin_client:delete("/consumers/foo"))
      assert.res_status(204, res)

      helpers.wait_until(function()
        local proxy_client = helpers.http_client("127.0.0.1", 9002)

        res = proxy_client:send({
          method  = "GET",
          path    = "/006-foo",
          headers = {["apikey"] = "my-key"},
        })

        local status = res and res.status
        proxy_client:close()
        if status == 401 then
          return true
        end
      end, 10)

      assert.logfile().has.line("[kong.sync.v2] new delta due to cascade deleting", true)
      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] delete entity", true)

      -- cascade deletion should be the same version

      local ver
      local count = 0
      local patt = "delete entity, version: %d+"
      local f = io.open("servroot2/logs/error.log", "r")
      while true do
        local line = f:read("*l")

        if not line then
          f:close()
          break
        end

        local found = line:match(patt)
        if found then
          ver = ver or found
          assert.equal(ver, found)
          count = count + 1
        end
      end
      assert(count > 1)

    end)
  end)

end)

end -- for _, strategy
