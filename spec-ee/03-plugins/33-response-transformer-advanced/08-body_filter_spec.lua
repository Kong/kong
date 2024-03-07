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

    bp.plugins:insert {
      route     = { id = route1.id },
      name      = "response-transformer-advanced",
      config    = {
        allow = {
          json      = {"headers"},
        }
      }
    }

    local route2 = bp.routes:insert({
      hosts = { "response2.test" },
    })

    bp.plugins:insert {
      route     = { id = route2.id },
      name      = "response-transformer-advanced",
      config    = {
      }
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
        path    = "/anything",
        headers = {
          host  = "response2.test"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.not_nil(json.url)
      assert.not_nil(json.headers)

      local res = assert(proxy_client:send {
        method  = "GET",
        path    = "/anything",
        headers = {
          host  = "response.test"
        }
      })
      local json = assert.response(res).has.jsonbody()
      assert.is_nil(json.url)
      assert.not_nil(json.headers)
    end)
  end)
end)
