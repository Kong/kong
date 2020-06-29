local helpers = require "spec.helpers"

local fmt = string.format

local SERVICE_YML = [[
- name: my-service-%d
  url: https://example%d.dev
  plugins:
  - name: key-auth
  routes:
  - name: my-route-%d
    paths:
    - /%d
]]

describe("Workers initialization #off", function()
  local admin_client, proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database   = "off",
      nginx_worker_processes = 1,
    }))

    admin_client = assert(helpers.admin_client())
    proxy_client = assert(helpers.proxy_client())
  end)

  lazy_teardown(function()
    admin_client:close()
    proxy_client:close()
    helpers.stop_kong(nil, true)
  end)

  it("restarts worker correctly without issues on the init_worker phase when config includes 1000+ plugins", function()
    local buffer = {"_format_version: '1.1'", "services:"}
    for i = 1, 1001 do
      buffer[#buffer + 1] = fmt(SERVICE_YML, i, i, i, i)
    end
    local config = table.concat(buffer, "\n")

    local res = admin_client:post("/config",{
      body = { config = config },
      headers = {
        ["Content-Type"] = "application/json"
      }
    })
    assert.res_status(201, res)

    helpers.signal_workers(nil, "-TERM")

    proxy_client:close()
    proxy_client = assert(helpers.proxy_client())

    local conf = helpers.get_running_conf()
    local _, code = helpers.execute("grep -F 'error building initial plugins iterator: plugins iterator was changed while rebuilding it' " ..
                                     conf.nginx_err_logs, true)
    local not_found = 1
    assert.equal(not_found, code)

    -- make a request to ensure that proxying is working
    -- (and to make some time for the worker to respawn)
    res = assert(proxy_client:get("/1", { headers = { host = "example1.dev" } }))
    assert.res_status(401, res)
  end)
end)

