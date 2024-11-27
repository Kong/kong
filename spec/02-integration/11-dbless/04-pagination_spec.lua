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
      log:
        - |
          return function(conf)
            local db = kong.db

            assert(db.routes.pagination.max_page_size == 2048)
          end
]]


local COUNT = 1001


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
