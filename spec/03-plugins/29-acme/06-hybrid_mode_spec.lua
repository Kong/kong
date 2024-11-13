local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy({"postgres"}) do
  describe("Plugin: acme (handler.access) worked with [#" .. strategy .. "]", function()
    local domain = "mydomain.test"

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, { "acme", })

      assert(bp.routes:insert {
        paths = { "/" },
      })

      assert(bp.plugins:insert {
        name = "acme",
        config = {
          account_email = "test@test.com",
          api_uri = "https://api.acme.org",
          domains = { domain },
          storage = "kong",
          storage_config = {
            kong = {},
          },
        },
      })

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
      helpers.stop_kong("servroot2")
      helpers.stop_kong()
    end)

    it("sanity test works with \"kong\" storage in Hybrid mode", function()
      local proxy_client = helpers.http_client("127.0.0.1", 9002)
      helpers.wait_until(function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/.well-known/acme-challenge/x",
          headers =  { host = domain }
        })

        if res.status ~= 404 then
          return false
        end

        local body = res:read_body()
        return body == "Not found\n"
      end, 10)
      proxy_client:close()
    end)
  end)
end
