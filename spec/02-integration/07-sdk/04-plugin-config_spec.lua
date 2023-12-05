-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local cjson = require "cjson"


describe("Plugin configuration", function()
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(nil, {
      "plugins",
    }, {
      "plugin-config-dump",
    })

    local route = bp.routes:insert({ hosts = { "test.test" } })

    bp.plugins:insert({
      name = "plugin-config-dump",
      instance_name = "test",
      route = { id = route.id },
      config = {},
    })

    assert(helpers.start_kong({
      plugins = "bundled,plugin-config-dump",
      nginx_conf = "spec/fixtures/custom_nginx.template",
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

  it("conf", function()
    local res = proxy_client:get("/request", {
      headers = { Host = "test.test" }
    })

    local body = assert.status(200, res)
    local json = cjson.decode(body)
    assert.equal("test", json.plugin_instance_name)
  end)
end)
