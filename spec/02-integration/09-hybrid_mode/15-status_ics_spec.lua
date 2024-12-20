-- 09-hybrid_mode/11-status_ready.lua
local helpers = require "spec.helpers"

local cp_status_port = helpers.get_available_port()
local dp_status_port = 8100

for _, v in ipairs({ {"on", "on"}, }) do
  local rpc, inc_sync = v[1], v[2]

for _, strategy in helpers.each_strategy() do

  describe("Hybrid Mode - status ready #" .. strategy .. " inc_sync=" .. inc_sync, function()

    helpers.get_db_utils(strategy, {})

    local function start_kong_dp()
      return helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "serve_dp",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "127.0.0.1:9002",
        nginx_main_worker_processes = 8,
        status_listen = "127.0.0.1:" .. dp_status_port,
        cluster_rpc = rpc,
        cluster_incremental_sync = inc_sync,
        log_level = "info",
      })
    end

    local function start_kong_cp()
      return helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        prefix = "serve_cp",
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        status_listen = "127.0.0.1:" .. cp_status_port,
        cluster_rpc = rpc,
        cluster_incremental_sync = inc_sync,
        log_level = "info",
      })
    end

    describe("dp status ready when inc_sync == on", function()
      lazy_setup(function()
        assert(start_kong_cp())
        assert(start_kong_dp())
      end)

      lazy_teardown(function()
          assert(helpers.stop_kong("serve_cp"))
          assert(helpers.stop_kong("serve_dp"))
      end)

      it("should return 200 on data plane after configuring #ttt", function()
        -- insert one entity to make dp ready for incremental sync
        if inc_sync == "on" then

          print("+++++ post /services")
          local admin_client = helpers.admin_client(10000)
          local res = assert(admin_client:post("/services", {
            body = { name = "service-001", url = "https://127.0.0.1:15556/request", },
            headers = {["Content-Type"] = "application/json"}
          }))
          assert.res_status(201, res)

          admin_client:close()

          helpers.wait_until(function()
            local http_client = helpers.http_client('127.0.0.1', dp_status_port)

            local res = http_client:send({
              method = "GET",
              path = "/status/ready",
            })

            local status = res and res.status
            http_client:close()

            if status == 200 then
              return true
            end
          end, 10)
        end
       end)
      end)
    end)
end -- for _, strategy
end -- for inc_sync
