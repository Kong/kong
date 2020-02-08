local helpers = require "spec.helpers"
local cjson   = require "cjson"


local md5 = ngx.md5


for _, strategy in helpers.each_strategy() do
  describe("Buffered Proxying [#" .. strategy .. "]", function()

    -- TODO: http2 / grpc does not currently work with
    -- ngx.location.capture that buffered proxying uses

    describe("[http]", function()
      local proxy_client
      local proxy_ssl_client
      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy, {
          "routes",
          "services",
          "plugins",
        }, {
          "enable-buffering",
        })

        local r1 = bp.routes:insert {
          paths = { "/1" },
        }

        bp.plugins:insert {
          name = "enable-buffering",
          route = r1,
          protocols = {
            "http",
            "https",
          },
          config = {
            mode = "md5-header"
          }
        }

        local r2 = bp.routes:insert {
          paths = { "/2" },
        }

        bp.plugins:insert {
          name = "enable-buffering",
          route = r2,
          protocols = {
            "http",
            "https",
          },
          config = {
            mode = "modify-json"
          }
        }

        assert(helpers.start_kong({
          database      = strategy,
          plugins       = "bundled,enable-buffering",
          nginx_conf    = "spec/fixtures/custom_nginx.template",
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

      it("header can be set from upstream response body", function()
        local res = proxy_client:get("/1/status/200")
        local body = assert.res_status(200, res)
        assert.equal(md5(body), res.headers["MD5"])

        local res = proxy_ssl_client:get("/1/status/234")
        local body = assert.res_status(234, res)
        assert.equal(md5(body), res.headers["MD5"])
      end)

      it("header can be set from upstream response body and body can be modified", function()
        local res = proxy_client:get("/2/status/200")
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])

        local res = proxy_ssl_client:get("/2/status/234")
        local body = assert.res_status(234, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])
      end)
    end)
  end)
end
