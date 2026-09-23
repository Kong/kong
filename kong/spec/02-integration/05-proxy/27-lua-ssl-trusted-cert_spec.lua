local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  local bp
  local postgres_only = strategy == "postgres" and it or pending

  describe("lua_ssl_trusted_cert #" .. strategy, function()
    before_each(function()
      bp = helpers.get_db_utils(strategy, {
        "routes",
        "plugins",
      })

      local r = bp.routes:insert({ hosts = {"test.dev"} })

      bp.plugins:insert({
        name = "pre-function",
        route = { id = r.id },
        config = {
          access = {
            string.format([[
                local tcpsock = ngx.socket.tcp()
                assert(tcpsock:connect("%s", %d))

                assert(tcpsock:sslhandshake(
                  nil,         -- reused_session
                  nil,         -- server_name
                  true         -- ssl_verify
                ))

                assert(tcpsock:close())
              ]],
              helpers.mock_upstream_ssl_host,
              helpers.mock_upstream_ssl_port
            )
          },
        },
      })
    end)

    after_each(function()
      helpers.stop_kong()
    end)

    it("works with single entry", function()
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_spec.crt",
      }))

      local proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/", {
        headers = { host = "test.dev" },
      })
      assert.res_status(200, res)
    end)

    it("works with multiple entries", function()
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering_ca.crt,spec/fixtures/kong_clustering.crt",
        ssl_cert = "spec/fixtures/kong_clustering.crt",
        ssl_cert_key = "spec/fixtures/kong_clustering.key",
      }))

      local proxy_client = helpers.proxy_client()

      local res = proxy_client:get("/", {
        headers = { host = "test.dev" },
      })
      assert.res_status(200, res)
    end)

    postgres_only("works with SSL verification", function()
      local _, err = helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        lua_ssl_trusted_certificate = "spec/fixtures/kong_clustering_ca.crt,spec/fixtures/kong_clustering.crt",
        pg_ssl = "on",
        pg_ssl_verify = "on",
      })

      assert.not_matches("error loading CA locations %(No such file or directory%)", err)
    end)
  end)
end


