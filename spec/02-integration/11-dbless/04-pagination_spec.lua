local helpers = require "spec.helpers"


local strategy = "off"

describe("dbless pagination #" .. strategy, function()
  local client, admin_client

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

    for i = 1, 1001 do
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
      nginx_conf = "spec/fixtures/custom_nginx.template",
      database = strategy,
      plugins = "bundled,dbless-pagination-test",
    }))
    print("helpers.start_kong")

    client = assert(helpers.proxy_client())
    admin_client = assert(helpers.admin_client())
  end)

  lazy_teardown(function()
    admin_client:close()
    client:close()
    helpers.stop_kong()
  end)

  it("Routes", function()

    local res = admin_client:get("/routes/my-route-1")
    assert.res_status(200, res)

    local res = assert(client:send {
      method = "GET",
      path = "/1",
    })
    assert.res_status(200, res)
    assert.same(res.headers["X-Rows-Number"], "512")
    assert.same(res.headers["X-Max-Page-Size"], "2048")
  end)
end)
