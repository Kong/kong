
local uh = require "spec/upgrade_helpers"


local OLD_KONG_VERSION = os.getenv("OLD_KONG_VERSION")
local handler = OLD_KONG_VERSION:sub(1,3) == "2.8" and describe or pending


handler("post-function plugin migration", function()

    lazy_setup(function()
      assert(uh.start_kong())
    end)

    lazy_teardown(function ()
      assert(uh.stop_kong())
    end)

    local custom_header_name = "X-Test-Header"
    local custom_header_content = "this is it"

    uh.setup(function ()
        local admin_client = uh.admin_client()
        local res = assert(admin_client:send {
            method = "POST",
            path = "/plugins/",
            body = {
              name = "post-function",
              config = {
                functions = {
                  "kong.response.set_header('" .. custom_header_name .. "', '" .. custom_header_content .. "')"
                }
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
        local res = uh.send_proxy_get_request()

        -- verify that HTTP response has had the header added by the plugin
        assert.equal(custom_header_content, res.headers[custom_header_name])
    end)
end)
