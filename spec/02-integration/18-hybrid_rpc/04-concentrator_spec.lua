local helpers = require "spec.helpers"
local cjson = require("cjson.safe")


-- keep it for future usage
local function obtain_dp_node_id()  -- luacheck: ignore
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


-- we need incremental sync to verify rpc
for _, inc_sync in ipairs { "on" } do
for _, strategy in helpers.each_strategy() do
  describe("Hybrid Mode RPC over DB concentrator #" .. strategy .. " inc_sync=" .. inc_sync, function()

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
        cluster_rpc = "on",
        cluster_incremental_sync = inc_sync, -- incremental sync
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        prefix = "servroot3",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        database = strategy,
        cluster_listen = "127.0.0.1:" .. helpers.get_available_port(),
        nginx_conf = "spec/fixtures/custom_nginx.template",
        cluster_rpc = "on",
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
        cluster_rpc = "on",
        cluster_incremental_sync = inc_sync, -- incremental sync
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong("servroot2")
      helpers.stop_kong("servroot3")
      helpers.stop_kong()
    end)

    -- TODO: test with other rpc
    --describe("XXX over RPC", function()
    --end)
  end)
end -- for _, strategy
end -- for inc_sync
