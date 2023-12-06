-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"


describe("Plugin: response-transformer-advanced (filter)", function()
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(nil, nil, {
      "response-transformer-advanced",
    })

    local route1 = bp.routes:insert({
      hosts = { "response.test" },
    })

    local route2 = bp.routes:insert({
      hosts = { "response2.test" },
    })

    local service1 = bp.services:insert({
      port = helpers.get_proxy_port(),
      host = helpers.get_proxy_ip(),
      path = "/big_decimals",
    })

    bp.routes:insert({
      strip_path = true,
      service = service1,
      paths = { "/foo" }
    })

    local route4 = bp.routes:insert({
      paths = { "/big_decimals" }
    })

    bp.plugins:insert {
      route     = { id = route1.id },
      name      = "response-transformer-advanced",
      config    = {
        replace = {
          body      = [[{"error": "non-sensitive message"}]],
          if_status = {"500"}
        }
      }
    }

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "response-transformer-advanced",
      config    = {
        replace = {
          body      = "plugin_text",
          if_status = {"401"},
        }
      }
    }

    bp.plugins:insert {
      route     = { id = route4.id },
      name      = "response-transformer-advanced",
      config    = {
        replace = {
          body      = "worng_body",
          if_status = {"500-599"}
        }
      }
    }

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "key-auth",
    }

    bp.plugins:insert {
      route     = { id = route4.id },
      name      = "request-termination",
      config = {
        body = '{"key":6.07526679167888E14}',
        content_type = "application/json",
        echo = false,
        status_code = 200
      }
    }

    local consumer1 = bp.consumers:insert {
      username = "consumer1"
    }

    bp.keyauth_credentials:insert {
      key = "foo1",
      consumer = { id = consumer1.id }
    }

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "bundled, response-transformer-advanced"
    }))
  end)

  lazy_teardown(function()
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

  describe("body", function()
    it("replace full body if status code matches", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/500",
        headers = {
          host  = "response.test"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.same("non-sensitive message", json.error)
    end)
    it("doesn't replace full body if status code doesn't match", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host  = "response.test"
        }
      })
      local body = assert.res_status(200, res)
      assert.not_same(body, [["error": "non-sensitive message"]])
    end)
    it("does not validate replaced body against content type", function()
      -- the replaced body will be "plugin_text" -> plain text
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/status/200",
        headers = {
          host  = "response2.test",
        }
      })
      -- we got a 401 due to no credentials provided
      local body = assert.res_status(401, res)
      local content_type = res.headers["content-type"]
      -- content type returned by key-auth is application/json
      assert.same("application/json; charset=utf-8", content_type)
      -- the plugin doesn’t validate the value in config.replace.body
      -- against the content type, so ensure that we pass the replaced
      -- body to the client even though the content type is different
      assert.equal("plugin_text", body)
    end)
    it("does not load raw response body(avoid encoding with cjson)", function()
      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/foo",
      })
      assert.equals("{\"key\":6.07526679167888E14}", res:read_body())
    end)
  end)
end)
