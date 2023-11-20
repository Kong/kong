-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local match          = require "luassert.match"
local pl_path        = require "pl.path"

local admin_gui      = require "kong.admin_gui"
local conf_loader    = require "kong.conf_loader"
local log            = require "kong.cmd.utils.log"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local helpers        = require "spec.helpers"

describe("admin_gui template", function()
  describe("admin_gui.generate_kconfig() - proxied", function()
    local mock_prefix  = "servroot"

    local conf = {
      prefix = mock_prefix,
      admin_gui_url = "http://0.0.0.0:8002",
      admin_gui_api_url = "https://admin-reference.kong-cloud.com",
      admin_gui_path = '/manager',
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
      -- XXX EE [[
      admin_gui_auth = 'basic-auth',
      admin_gui_auth_header = 'Kong-Admin-User',
      admin_gui_header_txt = "header_text",
      admin_gui_header_bg_color = "white",
      admin_gui_header_txt_color = "black",
      admin_gui_footer_txt = "footer_text",
      admin_gui_footer_bg_color = "red",
      admin_gui_footer_txt_color = "blue",
      admin_gui_login_banner_title = "banner_title",
      admin_gui_login_banner_body = "banner_body",
      rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
      -- XXX EE ]]
    }

    setup(function()
      prefix_handler.prepare_prefixed_interface_dir("/usr/local/kong", "gui", conf)
      assert(pl_path.isdir(mock_prefix))
    end)

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/manager'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_URL': 'https://admin-reference.kong-cloud.com'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
      -- XXX EE [[
      assert.matches("'ADMIN_GUI_AUTH': 'basic-auth'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': 'white'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'black'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': 'red'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'blue'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body'", kconfig_content, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", kconfig_content, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", kconfig_content, nil, true)
      -- XXX EE ]]
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_gui_path = '/manager'
      new_conf.admin_gui_api_url = 'http://localhost:8001'
      -- XXX EE [[
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"
      new_conf.admin_gui_auth_header = 'Kong-Admin-Userz'
      new_conf.admin_gui_header_txt = "header_text_2"
      new_conf.admin_gui_header_bg_color = "#f73333"
      new_conf.admin_gui_header_txt_color = "green"
      new_conf.admin_gui_footer_txt = "footer_text_2"
      new_conf.admin_gui_footer_bg_color = "#000000"
      new_conf.admin_gui_footer_txt_color = "yellow"
      new_conf.admin_gui_login_banner_title = "banner_title_2"
      new_conf.admin_gui_login_banner_body = "banner_body_2"
      -- XXX EE ]]

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/manager'", new_content, nil, true)
      assert.matches("'ADMIN_API_URL': 'http://localhost:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
      -- XXX EE [[
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': '#f73333'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'green'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': '#000000'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'yellow'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body_2'", new_content, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", new_content, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-Userz'", new_content, nil, true)
      -- XXX EE ]]
    end)
  end)

  describe("admin_gui.generate_kconfig() - not proxied", function()
    local mock_prefix  = "servroot"

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
      -- XXX EE [[
      admin_gui_auth = nil,
      admin_gui_auth_header = 'Kong-Admin-User',
      admin_gui_header_txt = "header_text",
      admin_gui_header_bg_color = "white",
      admin_gui_header_txt_color = "black",
      admin_gui_footer_txt = "footer_text",
      admin_gui_footer_bg_color = "red",
      admin_gui_footer_txt_color = "blue",
      admin_gui_login_banner_title = "banner_title",
      admin_gui_login_banner_body = "banner_body",
      rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
      -- XXX EE ]]
    }

    setup(function()
      prefix_handler.prepare_prefixed_interface_dir("/usr/local/kong", "gui", conf)
      assert(pl_path.isdir(mock_prefix))
    end)

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'false'", kconfig_content, nil, true)
      -- XXX EE [[
      assert.matches("'ADMIN_GUI_AUTH': ''", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': 'white'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'black'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': 'red'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'blue'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body'", kconfig_content, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", kconfig_content, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", kconfig_content, nil, true)
      -- XXX EE ]]
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.anonymous_reports = true
      -- XXX EE [[
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"
      new_conf.admin_gui_header_txt = "header_text_2"
      new_conf.admin_gui_header_bg_color = "#f73333"
      new_conf.admin_gui_header_txt_color = "green"
      new_conf.admin_gui_footer_txt = "footer_text_2"
      new_conf.admin_gui_footer_bg_color = "#000000"
      new_conf.admin_gui_footer_txt_color = "yellow"
      new_conf.admin_gui_login_banner_title = "banner_title_2"
      new_conf.admin_gui_login_banner_body = "banner_body_2"
      -- XXX EE ]]

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'true'", new_content, nil, true)
      -- XXX EE [[
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': '#f73333'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'green'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': '#000000'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'yellow'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title_2'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body_2'", new_content, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", new_content, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", new_content, nil, true)
      -- XXX EE ]]
    end)
  end)

  describe("prepare_admin() - message logs", function()
    local conf = assert(conf_loader(helpers.test_conf_path))

    local default_prefix = conf.prefix
    local mock_prefix  = "servroot_2"
    local usr_path = "servroot"
    local usr_interface_dir = "gui2"
    local usr_interface_path = usr_path .. "/" .. usr_interface_dir

    setup(function()
      conf.prefix = mock_prefix

      if not pl_path.exists(usr_interface_path) then
        assert(pl_path.mkdir(usr_interface_path))
      end
    end)

    teardown(function()
      if pl_path.exists(usr_interface_path) then
        assert(pl_path.rmdir(usr_interface_path))
      end

      -- reset prefix
      conf.prefix = default_prefix
    end)

    it("symlink creation should log out error", function()
      local spy_log = spy.on(log, "warn")

      finally(function()
        log.warn:revert()
        assert:unregister("matcher", "str_match")
      end)

      assert:register("matcher", "str_match", function (_state, arguments)
        local expected = arguments[1]
        return function(value)
          return string.match(value, expected) ~= nil
        end
      end)

      local coreutils_err_msg = "ln: failed to create symbolic link 'servroot_2/gui2': "
                 .. "No such file or directory\n"

      local bsd_err_msg = "ln: servroot_2/gui2: No such file or directory\n"

      prefix_handler.prepare_prefixed_interface_dir(usr_path, usr_interface_dir, conf)
      assert.spy(spy_log).was_called(1)
      assert.spy(spy_log).was_called_with(
        match.is_any_of(match.str_match(coreutils_err_msg), match.str_match(bsd_err_msg))
      )
    end)
  end)
end)
