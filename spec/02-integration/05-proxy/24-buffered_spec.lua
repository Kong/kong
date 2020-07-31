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
          "enable-buffering-response",
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
            phase = "header_filter",
            mode = "md5-header",
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
            phase = "header_filter",
            mode = "modify-json"
          }
        }

        local r3 = bp.routes:insert {
          paths = { "/3" },
        }

        bp.plugins:insert {
          name = "enable-buffering-response",
          route = r3,
          protocols = {
            "http",
            "https",
          },
          config = {
            phase = "response",
            mode = "md5-header",
          }
        }

        local r4 = bp.routes:insert {
          paths = { "/4" },
        }

        bp.plugins:insert {
          name = "enable-buffering-response",
          route = r4,
          protocols = {
            "http",
            "https",
          },
          config = {
            phase = "response",
            mode = "modify-json"
          }
        }

        assert(helpers.start_kong({
          database      = strategy,
          plugins       = "bundled,enable-buffering,enable-buffering-response",
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

      it("header can be set from upstream response body on header_filter phase", function()
        local res = proxy_client:get("/1/status/231")
        local body = assert.res_status(231, res)
        assert.equal(md5(body), res.headers["MD5"])

        local res = proxy_ssl_client:get("/1/status/232")
        local body = assert.res_status(232, res)
        assert.equal(md5(body), res.headers["MD5"])
      end)

      it("header can be set from upstream response body and body can be modified on header_filter phase", function()
        local res = proxy_client:get("/2/status/233")
        local body = assert.res_status(233, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])

        local res = proxy_ssl_client:get("/2/status/234")
        local body = assert.res_status(234, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])
      end)

      it("header can be set from upstream response body on response phase", function()
        local res = proxy_client:get("/3/status/235")
        local body = assert.res_status(235, res)
        assert.equal(md5(body), res.headers["MD5"])

        local res = proxy_ssl_client:get("/3/status/236")
        local body = assert.res_status(236, res)
        assert.equal(md5(body), res.headers["MD5"])
      end)

      it("header can be set from upstream response body and body can be modified on response phase", function()
        local res = proxy_client:get("/4/status/237")
        local body = assert.res_status(237, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])

        local res = proxy_ssl_client:get("/4/status/238")
        local body = assert.res_status(238, res)
        local json = cjson.decode(body)
        assert.equal(true, json.modified)
        assert.equal("yes", res.headers["Modified"])
      end)
    end)
  end)
end
