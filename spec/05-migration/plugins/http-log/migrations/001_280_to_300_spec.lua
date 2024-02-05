
local cjson = require "cjson"
local http_mock = require "spec.helpers.http_mock"

local uh = require "spec.upgrade_helpers"

-- we intentionally use a fixed port as this file may be loaded multiple times
-- to test the migration process. do not change it to use dynamic port.
local HTTP_PORT = 29100

local OLD_KONG_VERSION = os.getenv("OLD_KONG_VERSION")
local handler = OLD_KONG_VERSION:sub(1,3) == "2.8" and describe or pending

handler("http-log plugin migration", function()
    local mock
    lazy_setup(function()
      assert(uh.start_kong())
    end)

    lazy_teardown(function ()
      assert(uh.stop_kong(nil, true))
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

    before_each(function ()
        mock = http_mock.new(HTTP_PORT)
        mock:start()
    end)

    after_each(function ()
        mock:stop(true)
    end)

    uh.all_phases("expected log header is added", function ()
        uh.send_proxy_get_request()

        mock.eventually:has_request_satisfy(function(request)
            local headers = request.headers
            assert.not_nil(headers, "headers do not exist")
            -- verify that the log HTTP request had the configured header
            -- somehow ngx.req.get_headers() wants to return a table for a single value header
            -- I don't know why but it's not relevant to this test
            assert(custom_header_content == headers[custom_header_name] or custom_header_content == headers[custom_header_name][1])
        end)
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
