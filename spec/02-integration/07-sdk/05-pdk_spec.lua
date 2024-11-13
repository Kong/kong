local helpers = require "spec.helpers"


local uuid_pattern = "^" .. ("%x"):rep(8) .. "%-" .. ("%x"):rep(4) .. "%-"
.. ("%x"):rep(4) .. "%-" .. ("%x"):rep(4) .. "%-"
.. ("%x"):rep(12) .. "$"


describe("kong.plugin.get_id()", function()
  local proxy_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(nil, {
      "routes", -- other routes may interference with this test
      "plugins",
    }, {
      "get-plugin-id",
    })

    local route = assert(bp.routes:insert({ hosts = { "test.test" } }))

    assert(bp.plugins:insert({
      name = "get-plugin-id",
      instance_name = "test",
      route = { id = route.id },
      config = {},
    }))

    assert(helpers.start_kong({
      plugins = "bundled,get-plugin-id",
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
    assert.match(uuid_pattern, body)
  end)
end)
