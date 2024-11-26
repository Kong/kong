local fmt = string.format
local helpers = require "spec.helpers"


local SERVICE_YML = [[
- name: my-service-%d
  url: https://example%d.dev
  plugins:
  - name: dbless-pagination-test
  routes:
  - name: my-route-%d
    paths:
    - /%d
]]


describe("dbless pagination #off", function()
  local client

  lazy_setup(function()
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      database = "off",
      plugins = "bundled,dbless-pagination-test",
    }))
    print("helpers.start_kong")

    client = assert(helpers.proxy_client())
  end)

  lazy_teardown(function()
    client:close()
    helpers.stop_kong()
  end)

  it("Routes", function()
    local buffer = {"_format_version: '3.0'", "services:"}
    for i = 1, 1001 do
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

    local res = admin_client:get("/routes/my-route-1")
    print(res:read_body())
    print("-------")

    -- check routes number with :page() API
    --local res, err  = client:get("/1", {})

    local res = assert(client:send {
      method = "GET",
      path = "/1",
    })
    --print(require("inspect")(res))
    local resbody = res:read_body()
    print"--------"
    print(resbody)
    --assert.response(res).has.header("X-rows-number", "test")
  end)
end)
