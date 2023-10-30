-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers    = require "spec.helpers"
local ee_helpers = require("spec-ee.helpers")

describe("Admin GUI - portal and vitals", function()
  local client, reset_license_data

  lazy_setup(function()
    reset_license_data = ee_helpers.clear_license_env()
  end)

  after_each(function()
    helpers.stop_kong()
    if client then
      client:close()
    end
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    reset_license_data()
  end)

  it("should not enable portal and vitals without license and key", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
      portal = "on",
      vitals = "on",
    }))
    client = assert(helpers.admin_gui_client(nil, 9002))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })

    local kconfig = assert.res_status(200, res)
    assert.matches("'PORTAL': 'false'", kconfig, nil, true)
    assert.matches("'VITALS': 'false'", kconfig, nil, true)
  end)

  it("should not enable portal and vitals with license but no key", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
      portal = "on",
      vitals = "on",
      license_path = "spec-ee/fixtures/mock_license.json",
    }))
    client = assert(helpers.admin_gui_client(nil, 9002))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })

    local kconfig = assert.res_status(200, res)
    assert.matches("'PORTAL': 'false'", kconfig, nil, true)
    assert.matches("'VITALS': 'false'", kconfig, nil, true)
  end)

  it("should not enable portal and vitals with license but invalid key", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
      portal = "on",
      vitals = "on",
      license_path = "spec-ee/fixtures/mock_license.json",
      portal_and_vitals_key = "i-am-a-random-invalid-key"
    }))
    client = assert(helpers.admin_gui_client(nil, 9002))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })

    local kconfig = assert.res_status(200, res)
    assert.matches("'PORTAL': 'false'", kconfig, nil, true)
    assert.matches("'VITALS': 'false'", kconfig, nil, true)
  end)

  it("should enable portal and vitals with valid license and key", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
      portal = "on",
      vitals = "on",
      license_path = "spec-ee/fixtures/mock_license.json",
      portal_and_vitals_key = ee_helpers.get_portal_and_vitals_key(),
    }))
    client = assert(helpers.admin_gui_client(nil, 9002))

    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })

    local kconfig = assert.res_status(200, res)
    assert.matches("'PORTAL': 'true'", kconfig, nil, true)
    assert.matches("'VITALS': 'true'", kconfig, nil, true)
  end)
end)
