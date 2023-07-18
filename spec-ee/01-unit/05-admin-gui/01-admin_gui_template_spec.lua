-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local ee             = require "kong.enterprise_edition"

local pl_path = require "pl.path"
local log     = require "kong.cmd.utils.log"

local exists = helpers.path.exists

describe("admin_gui template", function()
  local conf = assert(conf_loader(helpers.test_conf_path))

  it("auto-generates SSL certificate and key", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    assert(exists(conf.admin_gui_ssl_cert_default))
    assert(exists(conf.admin_gui_ssl_cert_key_default))
  end)

  it("does not re-generate if they already exist", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    local cer = helpers.file.read(conf.admin_gui_ssl_cert_default)
    local key = helpers.file.read(conf.admin_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    assert.equal(cer, helpers.file.read(conf.admin_gui_ssl_cert_default))
    assert.equal(key, helpers.file.read(conf.admin_gui_ssl_cert_key_default))
  end)

  it("generates a different SSL certificate and key from the RESTful API", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    local cer, key = {}, {}
    cer[1] = helpers.file.read(conf.admin_gui_ssl_cert_default)
    key[1] = helpers.file.read(conf.admin_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
    cer[2] = helpers.file.read(conf.admin_ssl_cert_default)
    key[2] = helpers.file.read(conf.admin_ssl_cert_key_default)
    assert.not_equals(cer[1], cer[2])
    assert.not_equals(key[1], key[2])
  end)

  describe("prepare_admin() - proxied", function()
    local mock_prefix  = "servroot"

    local conf = {
      prefix = mock_prefix,
      admin_gui_auth = 'basic-auth',
      admin_gui_url = "http://0.0.0.0:8002",
      admin_gui_api_url = "https://admin-reference.kong-cloud.com",
      admin_gui_header_txt = "header_text",
      admin_gui_header_bg_color = "white",
      admin_gui_header_txt_color = "black",
      admin_gui_footer_txt = "footer_text",
      admin_gui_footer_bg_color = "red",
      admin_gui_footer_txt_color = "blue",
      admin_gui_login_banner_title = "banner_title",
      admin_gui_login_banner_body = "banner_body",
      proxy_url = "http://0.0.0.0:8000",
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
      rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
      admin_gui_auth_header = 'Kong-Admin-User',
      admin_gui_path = '/manager'
    }

    setup(function()
      ee.prepare_interface("/usr/local/kong", "gui", conf)
      assert(pl_path.isdir(mock_prefix))
    end)

    it("inserts the appropriate values", function()
      local admin_idx = ee.prepare_admin(conf)

      assert.matches("'ADMIN_GUI_AUTH': 'basic-auth'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/manager'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': 'https://admin-reference.kong-cloud.com'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': 'white'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'black'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': 'red'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'blue'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body'", admin_idx, nil, true)
      assert.matches("'KONG_EDITION': 'enterprise'", admin_idx, nil, true)
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_gui_path = '/kong-manager'
      new_conf.admin_gui_api_url = 'http://localhost:8001'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
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

      -- update template
      local admin_idx = ee.prepare_admin(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/kong-manager'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': 'http://localhost:8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-Userz'", admin_idx, nil, true)
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': '#f73333'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'green'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': '#000000'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'yellow'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body_2'", admin_idx, nil, true)
      assert.matches("'KONG_EDITION': 'enterprise'", admin_idx, nil, true)
    end)
  end)

  describe("prepare_admin() - not proxied", function()
    local mock_prefix  = "servroot"

    local conf = {
      prefix = mock_prefix,
      admin_gui_auth = nil,
      admin_gui_url = "http://0.0.0.0:8002",
      proxy_url = "http://0.0.0.0:8000",
      admin_gui_api_url = "0.0.0.0:8001",
      admin_gui_header_txt = "header_text",
      admin_gui_header_bg_color = "white",
      admin_gui_header_txt_color = "black",
      admin_gui_footer_txt = "footer_text",
      admin_gui_footer_bg_color = "red",
      admin_gui_footer_txt_color = "blue",
      admin_gui_login_banner_title = "banner_title",
      admin_gui_login_banner_body = "banner_body",
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
      rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
      admin_gui_auth_header = 'Kong-Admin-User',
    }

    setup(function()
      ee.prepare_interface("/usr/local/kong", "gui", conf)
      assert(pl_path.isdir(mock_prefix))
    end)

    it("inserts the appropriate values", function()
      local admin_idx = ee.prepare_admin(conf)

      assert.matches("'ADMIN_GUI_AUTH': ''", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", admin_idx, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'false'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': 'white'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'black'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': 'red'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'blue'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body'", admin_idx, nil, true)
      assert.matches("'KONG_EDITION': 'enterprise'", admin_idx, nil, true)
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"
      new_conf.anonymous_reports = true
      new_conf.admin_gui_header_txt = "header_text_2"
      new_conf.admin_gui_header_bg_color = "#f73333"
      new_conf.admin_gui_header_txt_color = "green"
      new_conf.admin_gui_footer_txt = "footer_text_2"
      new_conf.admin_gui_footer_bg_color = "#000000"
      new_conf.admin_gui_footer_txt_color = "yellow"
      new_conf.admin_gui_login_banner_title = "banner_title_2"
      new_conf.admin_gui_login_banner_body = "banner_body_2"

      -- update template
      local admin_idx = ee.prepare_admin(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", admin_idx, nil, true)
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", admin_idx, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'true'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT': 'header_text_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_BG_COLOR': '#f73333'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_HEADER_TXT_COLOR': 'green'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT': 'footer_text_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_BG_COLOR': '#000000'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_FOOTER_TXT_COLOR': 'yellow'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_TITLE': 'banner_title_2'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_LOGIN_BANNER_BODY': 'banner_body_2'", admin_idx, nil, true)
      assert.matches("'KONG_EDITION': 'enterprise'", admin_idx, nil, true)
    end)
  end)

  describe("prepare_admin() - message logs", function()
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

      -- reverts the spy stub & matcher
      log.warn:revert()
      assert:unregister("matcher", "correct")

      -- reset prefix
      conf.prefix = default_prefix
    end)

    it("symlink creation should log out error", function()
      local spy_log = spy.on(log, "warn")

      local err = "ln: failed to create symbolic link 'servroot_2/gui2': "
                 .. "No such file or directory\n"

      ee.prepare_interface(usr_path, usr_interface_dir, conf)
      assert.spy(spy_log).was_called(1)
      assert.spy(spy_log).was_called_with(err)
    end)
  end)
end)
