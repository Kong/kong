
local cjson = require "cjson"
local tablex = require "pl.tablex"

local uh = require "spec/upgrade_helpers"
local helpers = require "spec.helpers"
local http_server = helpers.http_server

local HTTP_PORT = helpers.get_available_port()

describe("http-log plugin migration", function()

    lazy_setup(function()
      assert(uh.start_kong())
    end)

    lazy_teardown(function ()
      assert(uh.stop_kong())
    end)

    local log_server_url = "http://localhost:" .. HTTP_PORT .. "/"

    local custom_header_name = "X-Test-Header"
    local custom_header_content = "this is it"

    uh.setup(function ()
        local admin_client = assert(uh.admin_client())
        local res = assert(admin_client:send {
            method = "POST",
            path = "/plugins/",
            body = {
              name = "http-log",
              config = {
                http_endpoint = log_server_url,
                headers = { [custom_header_name] = {custom_header_content} }
              }
            },
            headers = {
              ["Content-Type"] = "application/json"
            }
        })
        assert.res_status(201, res)
        admin_client:close()

        uh.create_example_service()
    end)

    uh.all_phases("expected log header is added", function ()
        local thread = http_server(HTTP_PORT, { timeout = 10 })

        uh.send_proxy_get_request()

        local ok, lines = thread:join()
        assert.truthy(ok)

        -- verify that the log HTTP request had the configured header
        local idx = tablex.find(lines, custom_header_name .. ": " .. custom_header_content)
        assert.not_nil(idx, lines)
    end)

    uh.new_after_finish("has updated http-log configuration", function ()
        local admin_client = assert(uh.admin_client())
        local res = assert(admin_client:send {
            method = "GET",
            path = "/plugins/"
        })
        local body = cjson.decode(assert.res_status(200, res))
        assert.equal(1, #body.data)
        assert.equal(custom_header_content, body.data[1].config.headers[custom_header_name])
        admin_client:close()
    end)
end)
