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


for _, inc_sync in ipairs { "on", "off"  } do
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC #" .. strategy .. " inc_sync=" .. inc_sync, function()

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
        cluster_incremental_sync = inc_sync, -- incremental sync
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
        cluster_incremental_sync = inc_sync, -- incremental sync
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    describe("Dynamic log level over RPC", function()
      it("can get the current log level", function()
        local dp_node_id = obtain_dp_node_id()

        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:get("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, json.timeout)
        assert.equal("debug", json.current_level)
        assert.equal("debug", json.original_level)
      end)

      it("can set the current log level", function()
        local dp_node_id = obtain_dp_node_id()

        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:put("/clustering/data-planes/" .. dp_node_id .. "/log-level",
                                            {
                                              headers = {
                                                ["Content-Type"] = "application/json",
                                              },
                                              body = {
                                                current_level = "info",
                                                timeout = 10,
                                              },
                                            }))
        assert.res_status(201, res)

        local res = assert(admin_client:get("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.near(10, json.timeout, 3)
        assert.equal("info", json.current_level)
        assert.equal("debug", json.original_level)
      end)

      it("set current log level to original_level turns off feature", function()
        local dp_node_id = obtain_dp_node_id()

        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:put("/clustering/data-planes/" .. dp_node_id .. "/log-level",
                                            {
                                              headers = {
                                                ["Content-Type"] = "application/json",
                                              },
                                              body = {
                                                current_level = "info",
                                                timeout = 10,
                                              },
                                            }))
        assert.res_status(201, res)

        local res = assert(admin_client:put("/clustering/data-planes/" .. dp_node_id .. "/log-level",
                                            {
                                              headers = {
                                                ["Content-Type"] = "application/json",
                                              },
                                              body = {
                                                current_level = "debug",
                                                timeout = 10,
                                              },
                                            }))
        assert.res_status(201, res)

        local res = assert(admin_client:get("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, json.timeout)
        assert.equal("debug", json.current_level)
        assert.equal("debug", json.original_level)
      end)

      it("DELETE turns off feature", function()
        local dp_node_id = obtain_dp_node_id()

        local admin_client = helpers.admin_client()
        finally(function()
          admin_client:close()
        end)

        local res = assert(admin_client:put("/clustering/data-planes/" .. dp_node_id .. "/log-level",
                                            {
                                              headers = {
                                                ["Content-Type"] = "application/json",
                                              },
                                              body = {
                                                current_level = "info",
                                                timeout = 10,
                                              },
                                            }))
        assert.res_status(201, res)

        local res = assert(admin_client:delete("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
        assert.res_status(204, res)

        local res = assert(admin_client:get("/clustering/data-planes/" .. dp_node_id .. "/log-level"))
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(0, json.timeout)
        assert.equal("debug", json.current_level)
        assert.equal("debug", json.original_level)
      end)
    end)
  end)
end -- for _, strategy
end -- for inc_sync
