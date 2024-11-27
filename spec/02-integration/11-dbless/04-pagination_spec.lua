local fmt = string.format
local helpers = require "spec.helpers"


local SERVICE_YML = [[
- name: my-service-%d
  url: https://example%d.dev
  routes:
  - name: my-route-%d
    paths:
    - /%d
]]


local POST_FUNC = [[
plugins:
  - name: key-auth
  - name: post-function
    config:
      rewrite:
        - |
          return function(conf)
            local db = kong.db

            -- check max_page_size

            assert(db.routes.pagination.max_page_size == 2048)
            assert(db.services.pagination.max_page_size == 2048)

            -- check each()

            local r, err = db.routes:each(1000)
            assert(r and not err)

            local r, err = db.routes:each(2047)
            assert(r and not err)

            local r, err = db.routes:each(2048)
            assert(r and not err)

            local r, err = db.routes:each(2049)
            assert(not r)
            assert(err == "[off] size must be an integer between 1 and 2048")

            -- check page()

            local entities, err = db.routes:page(1000)
            assert(#entities == 1000 and not err)

            local entities, err = db.routes:page(2047)
            assert(#entities == 2047 and not err)

            local entities, err = db.routes:page(2048)
            assert(#entities == 2048 and not err)
            ngx.log(ngx.INFO, "xxx #entities", #entities)

            local entities, err = db.routes:page(2049)
            assert(not entities)
            assert(err == "[off] size must be an integer between 1 and 2048")
          end
]]


local COUNT = 3000


describe("dbless pagination #off", function()
  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  it("Routes", function()
    local buffer = {"_format_version: '3.0'", POST_FUNC, "services:"}
    for i = 1, COUNT do
      buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    end

    local config = table.concat(buffer, "\n")

    local admin_client = assert(helpers.admin_client())
    local res = admin_client:post("/config",{
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json",
      }
    })
    assert.res_status(201, res)
    admin_client:close()

    assert(helpers.restart_kong({
        database = "off",
    }))

    local proxy_client = assert(helpers.proxy_client())

    res = assert(proxy_client:get("/1", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
  end)
end)
