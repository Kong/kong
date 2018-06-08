local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: request-transformer [#" .. strategy .. "]", function()
    local proxy_client

    setup(function()
      local bp, _, dao = helpers.get_db_utils(strategy)
      helpers.with_current_ws(nil, function()
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })

      bp.plugins:insert {
        route_id = route1.id,
        name     = "request-transformer",
        config   = {
          add = {
            body        = {"p1:v1"}
          }
        }
      }
      end, dao)

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        feature_conf_path = "spec/fixtures/ee/feature_request_transformer_limit_body.conf",
      }))
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end
    end)


    describe("with feature_flag request_transformation_limit_body on", function()
      it("changes body if request body size is less than limit", function()
        local res = assert(proxy_client:send {
          method  = "POST",
          path    = "/request",
          body    = {
            hello = "world",
          },
          headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            host             = "test1.com"
          }
        })
        assert.response(res).has.status(200)
        local value = assert.request(res).has.formparam("hello")
        assert.equals("world", value)
        local value = assert.request(res).has.formparam("p1")
        assert.equals("v1", value)
      end)
    end)
    it("doesn't change body if request body size is bigger than limit", function()
      local payload = string.rep("*", 128)
      local res = assert(proxy_client:send {
        method  = "POST",
        path    = "/request",
        body    = {
          hello = payload
        },
        headers = {
          ["Content-Type"] = "application/x-www-form-urlencoded",
          host             = "test1.com"
        }
      })
      assert.response(res).has.status(200)
      local value = assert.request(res).has.formparam("hello")
      assert.equals(payload, value)
      assert.request(res).has.no.formparam("p1")
    end)
  end)
end
