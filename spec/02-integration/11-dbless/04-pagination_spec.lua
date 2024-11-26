local helpers = require "spec.helpers"


local strategy = "off"

describe("dbless pagination #" .. strategy, function()
  local proxy_client, admin_client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services",
      "plugins",
    })

    bp.plugins:insert {
      name = "dbless-pagination-test",
      config = { },
    }

    for i = 1, 2050 do
      local service = assert(bp.services:insert {
        url = "https://example1.dev",
        name = "my-serivce-" .. i,
      })

      assert(bp.routes:insert({
        paths = { "/" .. i },
        service = service,
        name = "my-route-" .. i,
      }))
    end

    assert(helpers.start_kong({
      log_level = "info",
      nginx_conf = "spec/fixtures/custom_nginx.template",
      database = strategy,
      plugins = "bundled,dbless-pagination-test",
    }))
    print("helpers.start_kong")

    proxy_client = assert(helpers.proxy_client())
    admin_client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    admin_client:close()
    proxy_client:close()
    helpers.stop_kong()
  end)

  it("Routes", function()

    local res = admin_client:get("/routes/my-route-1")
    assert.res_status(200, res)

    local res = assert(proxy_client:get("/1?size=nil"))
    assert.res_status(200, res)
    assert.same(res.headers["X-Rows-Number"], "512")
    assert.same(res.headers["X-Max-Page-Size"], "2048")

    local res = assert(proxy_client:get("/1?size=2048"))
    assert.res_status(200, res)
    assert.same(res.headers["X-Rows-Number"], "512")

    local res = assert(proxy_client:get("/1?size=2049"))
    assert.res_status(200, res)
    assert.same(res.headers["X-Rows-Number"], "[off] size must be an integer between 1 and 2048")
  end)
end)
