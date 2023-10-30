-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local pl_path        = require "pl.path"

local admin_gui      = require "kong.admin_gui"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local helpers        = require "spec.helpers"
local ee_helpers     = require("spec-ee.helpers")

describe("admin_gui template", function()
  describe("admin_gui.generate_kconfig() - portal and vitals", function()
    local mock_prefix = "servroot"

    describe("without valid license and key", function()
      local conf = {
        prefix = mock_prefix,
        admin_gui_url = "http://0.0.0.0:8002",
        admin_gui_api_url = "0.0.0.0:8001",
        anonymous_reports = false,
        admin_gui_listeners = {
          {
            ip = "0.0.0.0",
            port = 8002,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8445,
            ssl = true,
          },
        },
        admin_listeners = {
          {
            ip = "0.0.0.0",
            port = 8001,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8444,
            ssl = true,
          }
        },
        proxy_listeners = {
          {
            ip = "0.0.0.0",
            port = 8000,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8443,
            ssl = true,
          }
        },
        portal = true,
        vitals = true,
      }

      setup(function()
        prefix_handler.prepare_prefixed_interface_dir("/usr/local/kong", "gui", conf)
        assert(pl_path.isdir(mock_prefix))
      end)

      it("should not enable portal and vitals", function()
        local kconfig_content = admin_gui.generate_kconfig(conf)

        assert.matches("'PORTAL': 'false'", kconfig_content, nil, true)
        assert.matches("'VITALS': 'false'", kconfig_content, nil, true)
      end)
    end)

    describe("with valid license but no key", function()
      local reset_license_data

      local conf = {
        prefix = mock_prefix,
        admin_gui_url = "http://0.0.0.0:8002",
        admin_gui_api_url = "0.0.0.0:8001",
        anonymous_reports = false,
        admin_gui_listeners = {
          {
            ip = "0.0.0.0",
            port = 8002,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8445,
            ssl = true,
          },
        },
        admin_listeners = {
          {
            ip = "0.0.0.0",
            port = 8001,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8444,
            ssl = true,
          }
        },
        proxy_listeners = {
          {
            ip = "0.0.0.0",
            port = 8000,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8443,
            ssl = true,
          }
        },
        portal = true,
        vitals = true,
      }

      setup(function()
        reset_license_data = ee_helpers.clear_license_env()
        helpers.setenv("KONG_LICENSE_PATH", "spec-ee/fixtures/mock_license.json")
        prefix_handler.prepare_prefixed_interface_dir("/usr/local/kong", "gui", conf)
        assert(pl_path.isdir(mock_prefix))
      end)

      it("should not enable portal and vitals", function()
        local kconfig_content = admin_gui.generate_kconfig(conf)

        assert.matches("'PORTAL': 'false'", kconfig_content, nil, true)
        assert.matches("'VITALS': 'false'", kconfig_content, nil, true)
      end)

      lazy_teardown(function()
        reset_license_data()
      end)
    end)

    describe("with valid license and key", function()
      local reset_license_data, restore_kong_globals

      local save_kong_globals = function()
        local saved_g_kong = _G.kong
        local saved_kong_conf = kong.configuration

        _G.kong = {}
        kong.configuration = {}

        return function()
          _G.kong = saved_g_kong
          kong.configuration = saved_kong_conf
        end
      end

      local conf = {
        prefix = mock_prefix,
        admin_gui_url = "http://0.0.0.0:8002",
        admin_gui_api_url = "0.0.0.0:8001",
        anonymous_reports = false,
        admin_gui_listeners = {
          {
            ip = "0.0.0.0",
            port = 8002,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8445,
            ssl = true,
          },
        },
        admin_listeners = {
          {
            ip = "0.0.0.0",
            port = 8001,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8444,
            ssl = true,
          }
        },
        proxy_listeners = {
          {
            ip = "0.0.0.0",
            port = 8000,
            ssl = false,
          },
          {
            ip = "0.0.0.0",
            port = 8443,
            ssl = true,
          }
        },
        portal = true,
        vitals = true,
      }

      setup(function()
        reset_license_data = ee_helpers.clear_license_env()
        helpers.setenv("KONG_LICENSE_PATH", "spec-ee/fixtures/mock_license.json")

        -- portal_and_vitals_allowed() reads from kong.configuration.portal_and_vitals_key
        restore_kong_globals = save_kong_globals()
        kong.configuration.portal_and_vitals_key = ee_helpers.get_portal_and_vitals_key()

        prefix_handler.prepare_prefixed_interface_dir("/usr/local/kong", "gui", conf)
        assert(pl_path.isdir(mock_prefix))
      end)

      it("should enable portal and vitals", function()
        local kconfig_content = admin_gui.generate_kconfig(conf)

        assert.matches("'PORTAL': 'true'", kconfig_content, nil, true)
        assert.matches("'VITALS': 'true'", kconfig_content, nil, true)
      end)

      lazy_teardown(function()
        restore_kong_globals()
        reset_license_data()
      end)
    end)
  end)
end)
