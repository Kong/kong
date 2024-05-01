local helpers = require "spec.helpers"
local cjson = require("cjson.safe")


local function obtain_dp_node_id()
  local dp_node_id

  helpers.wait_until(function()
    local admin_client = helpers.admin_client()
    finally(function()
      admin_client:close()
    end)

    local res = assert(admin_client:get("/clustering/data-planes"))
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)

    for _, v in pairs(json.data) do
      if v.ip == "127.0.0.1" and ngx.time() - v.last_seen < 3 then
        dp_node_id = v.id
        return true
      end
    end
  end, 10)

  return dp_node_id
end


for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC over DB concentrator #" .. strategy, function()

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
        admin_listen = "127.0.0.1:" .. helpers.get_available_port(),
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        prefix = "servroot3",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:" .. helpers.get_available_port(),
        nginx_conf = "spec/fixtures/custom_nginx.template",
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
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong("servroot3")
      helpers.stop_kong()
    end)

    describe("Dynamic log level over RPC", function()
      pending("can get the current log level", function()
        local dp_node_id = obtain_dp_node_id()

        -- this sleep is *not* needed for the below wait_until to succeed,
        -- but it makes the wait_until tried succeed sooner because this
        -- extra time gives the concentrator enough time to report the node is
        -- online inside the DB. Without it, the first call to "/log-level"
        -- will always timeout after 5 seconds
        ngx.sleep(1)

        helpers.wait_until(function()
          local admin_client = helpers.admin_client()
          finally(function()
            admin_client:close()
          end)

          local res = assert(admin_client:get("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
          if res.status == 200 then
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(0, json.timeout)
            assert.equal("debug", json.current_level)
            assert.equal("debug", json.original_level)
            return true
          end
        end, 10)
      end)
    end)
  end)
end
