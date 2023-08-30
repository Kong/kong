local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("Plugin: key-auth (access) [#" .. strategy .. "] auto-expiring keys", function()
    -- Give a bit of time to reduce test flakyness on slow setups
    local ttl = 10
    local inserted_at
    local proxy_client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "consumers",
        "keyauth_credentials",
      })

      local r = bp.routes:insert {
        hosts = { "key-ttl-hybrid.com" },
      }

      bp.plugins:insert {
        name = "key-auth",
        route = { id = r.id },
      }

      local user_jafar = bp.consumers:insert {
        username = "Jafar",
      }

      bp.keyauth_credentials:insert({
        key = "kong",
        consumer = { id = user_jafar.id },
      }, { ttl = ttl })

      ngx.update_time()
      inserted_at = ngx.now()

      assert(helpers.start_kong({
        role = "control_plane",
        database = strategy,
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_listen = "127.0.0.1:9005",
        cluster_telemetry_listen = "127.0.0.1:9006",
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      assert(helpers.start_kong({
        role = "data_plane",
        database = "off",
        prefix = "servroot2",
        cluster_cert = "spec/fixtures/kong_clustering.crt",
        cluster_cert_key = "spec/fixtures/kong_clustering.key",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering.crt",
        cluster_control_plane = "127.0.0.1:9005",
        cluster_telemetry_endpoint = "127.0.0.1:9006",
        proxy_listen = "0.0.0.0:9002",
      }))
    end)

    lazy_teardown(function()
      if proxy_client then
        proxy_client:close()
      end

      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("authenticate for up to 'ttl'", function()
      helpers.wait_until(function()
        proxy_client = helpers.http_client("127.0.0.1", 9002)
        res = assert(proxy_client:send {
          method  = "GET",
          path  = "/status/200",
          headers = {
            ["Host"] = "key-ttl-hybrid.com",
            ["apikey"] = "kong",
          }
        })

        proxy_client:close()
        return res and res.status == 200
      end, 5)

      ngx.update_time()
      local elapsed = ngx.now() - inserted_at

      helpers.wait_until(function()
        proxy_client = helpers.http_client("127.0.0.1", 9002)
        res = assert(proxy_client:send {
          method  = "GET",
          path  = "/status/200",
          headers = {
            ["Host"] = "key-ttl-hybrid.com",
            ["apikey"] = "kong",
          }
        })

        proxy_client:close()
        return res and res.status == 401
      end, ttl - elapsed + 1)

    end)
  end)
end
