local helpers = require("spec.helpers")

local uuid_pattern = "^" .. ("%x"):rep(11) .. "%-" .. ("%x"):rep(4) .. "%-"
                         .. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
                         .. ("%x"):rep(12) .. "$"
local fixtures_dp = {
  http_mock = {},
}

fixtures_dp.http_mock.my_server_block = [[
  server {
      server_name my_server;
      listen 62349;

      location = "/hello" {
        content_by_lua_block {
          ngx.say(200, kong.cluster.get_id())
        }
      }
  }
]]


local fixtures_cp = {
  http_mock = {},
}

fixtures_cp.http_mock.my_server_block = [[
  server {
      server_name my_server;
      listen 62350;

      location = "/hello" {
        content_by_lua_block {
          ngx.say(200, kong.cluster.get_id())
        }
      }
  }
]]

for _, strategy in helpers.each_strategy() do
  describe("SDK: kong.cluster for #" .. strategy, function()
    local proxy_client

    lazy_setup(function()
      assert(helpers.get_db_utils(strategy, {
        "plugins",
        "routes",
        "services",
        "upstreams",
        "targets",
      }))

      assert(helpers.start_kong({
        role = "control_plane",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        database = strategy,
        db_update_frequency = 0.1,
        cluster_listen = "127.0.0.1:9005",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures_cp))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        proxy_listen = "0.0.0.0:9002",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }, nil, nil, fixtures_dp))
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("kong.cluster.get_id() in Hybrid mode", function()
      proxy_client = helpers.http_client(helpers.get_proxy_ip(false), 62350)

      local res = proxy_client:get("/hello")
      local cp_cluster_id = assert.response(res).has_status(200)

      assert.match(uuid_pattern, cp_cluster_id)

      proxy_client:close()

      helpers.wait_until(function()
        proxy_client = helpers.http_client(helpers.get_proxy_ip(false), 62349)
        local res = proxy_client:get("/hello")
        local body = assert.response(res).has_status(200)
        proxy_client:close()

        if string.match(body, uuid_pattern) then
          if cp_cluster_id == body then
            return true
          end
        end
      end, 10)
    end)
  end)
end
