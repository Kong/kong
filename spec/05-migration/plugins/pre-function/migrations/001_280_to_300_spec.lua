-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

local OLD_KONG_VERSION = os.getenv("OLD_KONG_VERSION")
local handler = OLD_KONG_VERSION:sub(1,8) == "next/2.8" and describe or pending

handler("pre-function plugin migration", function()

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
              name = "pre-function",
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

