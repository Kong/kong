local helpers = require "spec.helpers"
local cjson = require("cjson.safe")

local function start_cp(strategy, port)
  assert(helpers.start_kong({
    role = "control_plane",
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    database = strategy,
    cluster_listen = "127.0.0.1:" .. port,
    nginx_conf = "spec/fixtures/custom_nginx.template",
    cluster_rpc = "on",
    cluster_rpc_sync = "on", -- rpc sync
  }))
end

local function start_dp(prefix, port)
  assert(helpers.start_kong({
    role = "data_plane",
    database = "off",
    prefix = prefix,
    cluster_cert = "spec/fixtures/kong_clustering.crt",
    cluster_cert_key = "spec/fixtures/kong_clustering.key",
    cluster_control_plane = "127.0.0.1:9005",
    proxy_listen = "0.0.0.0:" .. port,
    nginx_conf = "spec/fixtures/custom_nginx.template",
    nginx_worker_processes = 4, -- multiple workers
    cluster_rpc = "on",
    cluster_rpc_sync = "on", -- rpc sync
    worker_state_update_frequency = 1,
  }))
end

local function test_url(path, port, code)
  helpers.wait_until(function()
    local proxy_client = helpers.http_client("127.0.0.1", port)

    local res = proxy_client:send({
      method  = "GET",
      path    = path,
    })

    local status = res and res.status
    proxy_client:close()
    if status == code then
      return true
    end
  end, 10)
end

for _, strategy in helpers.each_strategy() do

describe("Incremental Sync RPC #" .. strategy, function()

  lazy_setup(function()
    helpers.get_db_utils(strategy, {
      "clustering_data_planes",
    }) -- runs migrations

    start_cp(strategy, 9005)
    start_dp("servroot2", 9002)
    start_dp("servroot3", 9003)
  end)

  lazy_teardown(function()
    helpers.stop_kong("servroot2")
    helpers.stop_kong("servroot3")
    helpers.stop_kong()
  end)

  describe("sync works with multiple DP nodes", function()

    it("adding/removing routes", function()
      local admin_client = helpers.admin_client(10000)
      finally(function()
        admin_client:close()
      end)

      local res = assert(admin_client:post("/services", {
        body = { name = "service-001", url = "https://127.0.0.1:15556/request", },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)

      -- add a route

      res = assert(admin_client:post("/services/service-001/routes", {
        body = { paths = { "/001" }, },
        headers = {["Content-Type"] = "application/json"}
      }))
      assert.res_status(201, res)
      local body = assert.res_status(201, res)
      local json = cjson.decode(body)
      local route_id = json.id

      test_url("/001", 9002, 200)
      assert.logfile("servroot2/logs/error.log").has.line("[kong.sync.v2] update entity", true)

      test_url("/001", 9003, 200)
      assert.logfile("servroot3/logs/error.log").has.line("[kong.sync.v2] update entity", true)

      -- remove a route

      res = assert(admin_client:delete("/services/service-001/routes/" .. route_id))
      assert.res_status(204, res)

      test_url("/001", 9002, 404)
      test_url("/001", 9003, 404)
    end)
  end)
end)

end -- for _, strategy
