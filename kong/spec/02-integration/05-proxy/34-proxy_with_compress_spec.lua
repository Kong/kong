local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("Proxy with compressor [#" .. strategy .. "]", function()

    describe("[http] brotli", function()
      local proxy_client
      local proxy_ssl_client
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        })

        local s0 = bp.services:insert {
          name = "service0",
        }

        bp.routes:insert {
          paths = { "/0" },
          service = s0,
        }

        assert(helpers.start_kong({
          database      = strategy,
          nginx_conf    = "spec/fixtures/custom_nginx.template",
          nginx_proxy_brotli = "on",
          nginx_proxy_brotli_comp_level = 6,
          nginx_proxy_brotli_types = "text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript text/x-js",
          stream_listen = "off",
          admin_listen  = "off",
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
      end)

      before_each(function()
        proxy_client = helpers.proxy_client()
        proxy_ssl_client = helpers.proxy_ssl_client()
      end)

      after_each(function()
        if proxy_client then
          proxy_client:close()
        end

        if proxy_ssl_client then
          proxy_ssl_client:close()
        end
      end)

      it("header can be set when brotli compressor works fine", function()
        local res = proxy_client:get("/0/xml", {
          headers = {
            ["Accept-Encoding"] = "br",
            ["Content-Type"] = "application/xml",
          }
        })
        assert.res_status(200, res)
        assert.equal("br", res.headers["Content-Encoding"])
      end)
    end)
  end)
end
