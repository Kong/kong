local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("node id persistence", function()

    local control_plane_config = {
      role = "control_plane",
      prefix = "servroot1",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_listen = "127.0.0.1:9005",
    }

    local data_plane_config = {
      log_levle = "info",
      role = "data_plane",
      prefix = "servroot2",
      cluster_cert = "spec/fixtures/kong_clustering.crt",
      cluster_cert_key = "spec/fixtures/kong_clustering.key",
      cluster_control_plane = "127.0.0.1:9005",
      proxy_listen = "0.0.0.0:9002",
      database = "off",
    }

    local admin_client

    setup(function()
      helpers.get_db_utils(strategy, {
        "clustering_data_planes",
        "consumers",
      }) -- runs migrations

      assert(helpers.start_kong(control_plane_config))
      assert(helpers.start_kong(data_plane_config))

      admin_client = assert(helpers.admin_client())
    end)

    teardown(function()
      if admin_client then
        admin_client:close()
      end
      helpers.stop_kong("servroot1")
      helpers.stop_kong("servroot2")
    end)

    it("registed data plane number should not increased after same data plane restarted", function()
      local node_id
      helpers.pwait_until(function()
        local res = assert(admin_client:send {
          method = "GET",
          path = "/clustering/data-planes",
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(1, #json.data)
        node_id = json.data[1].id
        return true
      end, 10, 1)

      helpers.clean_logfile("servroot2/logs/error.log")
      assert(helpers.restart_kong(data_plane_config))

      ngx.sleep(20) -- sleep because data plane needs to take some time before it connect to CP

      local res = assert(admin_client:send {
        method = "GET",
        path = "/clustering/data-planes",
      })
      assert.response(res).has.status(200)
      local json = assert.response(res).has.jsonbody()
      assert.equal(1, #json.data)
      assert.equal(node_id, json.data[1].id)
    end)
  end)

end
