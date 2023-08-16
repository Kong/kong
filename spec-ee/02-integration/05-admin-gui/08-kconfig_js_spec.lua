-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"

describe("Admin GUI config", function ()
  it("should be reloaded and invalidate kconfig.js cache", function()

    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9012",
      admin_gui_url = "http://test1.example.com"
    }))

    finally(function()
      helpers.stop_kong()
    end)

    local client = assert(ee_helpers.admin_gui_client(nil, 9012))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'ADMIN_GUI_URL': 'http://test1.example.com'", res, nil, true)

    client:close()

    assert(helpers.reload_kong("reload --conf " .. helpers.test_conf_path, {
      database = "off",
      admin_gui_listen = "127.0.0.1:9012",
      admin_gui_url = "http://test2.example.com",
      admin_gui_path = "/manager",
      timeout = 30,
    }))

    ngx.sleep(1)    -- to make sure older workers are gone

    client = assert(ee_helpers.admin_gui_client(nil, 9012))
    res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    assert.res_status(404, res)

    res = assert(client:send {
      method = "GET",
      path = "/manager/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'ADMIN_GUI_URL': 'http://test2.example.com'", res, nil, true)
    client:close()
  end)
end)
