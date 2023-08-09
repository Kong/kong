local pl_path        = require "pl.path"

local helpers        = require "spec.helpers"
local admin_gui      = require "kong.admin_gui"
local conf_loader    = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local log            = require "kong.cmd.utils.log"

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

  describe("admin_gui.generate_kconfig() - proxied", function()
    local conf = {
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
    }

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/manager'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_URL': 'https://admin-reference.kong-cloud.com'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
      assert.matches("'KONG_EDITION': 'community'", kconfig_content, nil, true)
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_gui_path = '/manager'
      new_conf.admin_gui_api_url = 'http://localhost:8001'

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_GUI_PATH': '/manager'", new_content, nil, true)
      assert.matches("'ADMIN_API_URL': 'http://localhost:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
      assert.matches("'KONG_EDITION': 'community'", new_content, nil, true)
    end)
  end)

  describe("admin_gui.generate_kconfig() - not proxied", function()
    local conf = {
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
    }

    it("should generates the appropriate kconfig", function()
      local kconfig_content = admin_gui.generate_kconfig(conf)

      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", kconfig_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", kconfig_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'false'", kconfig_content, nil, true)
      assert.matches("'KONG_EDITION': 'community'", kconfig_content, nil, true)
    end)

    it("should regenerates the appropriate kconfig from another call", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.anonymous_reports = true

      -- regenerate kconfig
      local new_content = admin_gui.generate_kconfig(new_conf)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", new_content, nil, true)
      assert.matches("'ADMIN_API_URL': '0.0.0.0:8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", new_content, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", new_content, nil, true)
      assert.matches("'ANONYMOUS_REPORTS': 'true'", new_content, nil, true)
      assert.matches("'KONG_EDITION': 'community'", new_content, nil, true)
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

      prefix_handler.prepare_prefixed_interface_dir(usr_path, usr_interface_dir, conf)
      assert.spy(spy_log).was_called(1)
      assert.spy(spy_log).was_called_with(err)
    end)
  end)
end)
