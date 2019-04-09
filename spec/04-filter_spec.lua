local helpers = require "spec.helpers"


for _, strategy in helpers.each_strategy() do
  describe("Plugin: response-transformer-advanced (filter)", function()
    local proxy_client

    setup(function()
      local bp = helpers.get_db_utils(strategy)


      local route1 = bp.routes:insert({
        hosts = { "response.com" },
      })

      local route2 = bp.routes:insert({
        hosts = { "response2.com" },
      })

      bp.plugins:insert {
        route    = { id = route1.id },
        name     = "response-transformer-advanced",
        config   = {
          remove    = {
            headers = {"Access-Control-Allow-Origin"},
            json    = {"url"}
          }
        }
      }

      bp.plugins:insert {
        route    = { id = route2.id },
        name     = "response-transformer-advanced",
        config   = {
          replace = {
            json  = {"headers:/hello/world", "uri_args:this is a / test", "url:\"wot\""}
          }
        }
      }

      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins    = "bundled, response-transformer-advanced"
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

    describe("parameters", function()
      it("remove a parameter", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "response.com"
          }
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.is_nil(json.url)
      end)
      it("remove a header", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/response-headers",
          headers = {
            host  = "response.com"
          }
        })
        assert.response(res).has.status(200)
        assert.response(res).has.jsonbody()
        assert.response(res).has.no.header("acess-control-allow-origin")
      end)
      it("replace a body parameter on GET", function()
        local res = assert(proxy_client:send {
          method  = "GET",
          path    = "/get",
          headers = {
            host  = "response2.com"
          }
        })
        assert.response(res).status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equals([[/hello/world]], json.headers)
        assert.equals([["wot"]], json.url)
        assert.equals([[this is a / test]], json.uri_args)
      end)
    end)
  end)
end
