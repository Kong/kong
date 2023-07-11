-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local lfs = require "lfs"
local pl_path = require "pl.path"
local helpers = require "spec.helpers"
local ee_helpers = require "spec-ee.helpers"
local test_prefix = helpers.test_conf.prefix

local _

describe("Admin GUI - admin_gui_path", function()
  local client

  after_each(function()
    helpers.stop_kong()
    if client then
      client:close()
    end
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  it("should serve Admin GUI correctly when admin_gui_path is unset", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
    }))

    local err, gui_dir_path, gui_index_file_path
    gui_dir_path = pl_path.join(test_prefix, "gui")
    os.execute("rm -rf " .. gui_dir_path)
    _, err = lfs.mkdir(gui_dir_path)
    assert.is_nil(err)

    gui_index_file_path = pl_path.join(gui_dir_path, "index.html")

    local gui_index_file
    gui_index_file, err = io.open(gui_index_file_path, "w+")
    assert.is_nil(err)
    gui_index_file:write("TEST INDEX.HTML = /__km_base__/assets/image.png")
    gui_index_file:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    local res = assert(client:send {
      method = "GET",
      path = "/",
    })
    res = assert.res_status(200, res)
    assert.matches("TEST INDEX%.HTML = /assets/image%.png", res)
    client:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'RBAC_ENFORCED': 'false'", res, nil, true)
    assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", res, nil, true)
    assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", res, nil, true)
    assert.matches("'RBAC': 'off'", res, nil, true)
    assert.matches("'ADMIN_GUI_PATH': '/'", res, nil, true)
  end)

  it("should serve Admin GUI correctly when admin_gui_path is set", function()
    assert(helpers.start_kong({
      database = "off",
      admin_gui_listen = "127.0.0.1:9002",
      admin_gui_path = "/manager",
    }))

    local err, gui_dir_path, gui_index_file_path
    gui_dir_path = pl_path.join(test_prefix, "gui")
    os.execute("rm -rf " .. gui_dir_path)
    _, err = lfs.mkdir(gui_dir_path)
    assert.is_nil(err)

    gui_index_file_path = pl_path.join(gui_dir_path, "index.html")

    local gui_index_file
    gui_index_file, err = io.open(gui_index_file_path, "w+")
    assert.is_nil(err)
    gui_index_file:write("TEST INDEX.HTML = /__km_base__/assets/image.png")
    gui_index_file:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    local res = assert(client:send {
      method = "GET",
      path = "/",
    })
    assert.res_status(404, res)
    client:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    res = assert(client:send {
      method = "GET",
      path = "/manager",
    })
    res = assert.res_status(200, res)
    assert.matches("TEST INDEX%.HTML = /manager/assets/image%.png", res)
    client:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    local res = assert(client:send {
      method = "GET",
      path = "/kconfig.js",
    })
    assert.res_status(404, res)
    client:close()

    client = assert(ee_helpers.admin_gui_client(nil, 9002))
    res = assert(client:send {
      method = "GET",
      path = "/manager/kconfig.js",
    })
    res = assert.res_status(200, res)
    assert.matches("'RBAC_ENFORCED': 'false'", res, nil, true)
    assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", res, nil, true)
    assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", res, nil, true)
    assert.matches("'RBAC': 'off'", res, nil, true)
    assert.matches("'ADMIN_GUI_PATH': '/manager'", res, nil, true)
  end)
end)
