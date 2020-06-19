local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local ee             = require "kong.enterprise_edition"

local pl_file = require "pl.file"
local pl_path = require "pl.path"
local match   = require "luassert.match"
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
    local idx_filename = mock_prefix .. "/gui_config/kconfig.js"

    local conf = {
      prefix = mock_prefix,
      admin_gui_auth = 'basic-auth',
      admin_gui_url = "http://0.0.0.0:8002",
      admin_api_uri = "https://admin-reference.kong-cloud.com",
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
    }

    setup(function()
      helpers.execute("rm -f " .. idx_filename)
      ee.prepare_admin(conf)
      assert(pl_path.isdir(mock_prefix))
      assert(pl_path.isfile(idx_filename))
    end)

    teardown(function()
      if pl_path.isfile(idx_filename) then
        pl_file.delete(idx_filename)
      end
    end)

    it("inserts the appropriate values", function()
      local admin_idx = pl_file.read(idx_filename)

      assert.matches("'ADMIN_GUI_AUTH': 'basic-auth'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_URL': 'http://0.0.0.0:8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': 'https://admin-reference.kong-cloud.com'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-User'", admin_idx, nil, true)
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_api_uri = 'http://localhost:8001'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"
      new_conf.admin_gui_auth_header = 'Kong-Admin-Userz'

      -- update template
      ee.prepare_admin(new_conf)
      local admin_idx = pl_file.read(idx_filename)

      -- test configuration values against template
      assert.matches("'ADMIN_GUI_URL': 'http://admin-test.example.com'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_PORT': '8002'", admin_idx, nil, true)
      assert.matches("'ADMIN_GUI_SSL_PORT': '8445'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_URL': 'http://localhost:8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_PORT': '8001'", admin_idx, nil, true)
      assert.matches("'ADMIN_API_SSL_PORT': '8444'", admin_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", admin_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", admin_idx, nil, true)
      assert.matches("'RBAC_USER_HEADER': 'Kong-Admin-Userz'", admin_idx, nil, true)
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", admin_idx, nil, true)
    end)
  end)

  describe("prepare_admin() - not proxied", function()
    local mock_prefix  = "servroot"
    local idx_filename = mock_prefix .. "/gui_config/kconfig.js"

    local conf = {
      prefix = mock_prefix,
      admin_gui_auth = nil,
      admin_gui_url = "http://0.0.0.0:8002",
      proxy_url = "http://0.0.0.0:8000",
      admin_api_uri = "0.0.0.0:8001",
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
      helpers.execute("rm -f " .. idx_filename)
      ee.prepare_admin(conf)
      assert(pl_path.isdir(mock_prefix))
      assert(pl_path.isfile(idx_filename))
    end)

    teardown(function()
      if pl_path.isfile(idx_filename) then
        pl_file.delete(idx_filename)
      end
    end)

    it("inserts the appropriate values", function()
      local admin_idx = pl_file.read(idx_filename)

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
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"
      new_conf.anonymous_reports = true

      -- update template
      ee.prepare_admin(new_conf)
      assert(pl_path.isfile(idx_filename))
      local admin_idx = pl_file.read(idx_filename)

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
    end)
  end)

  describe("prepare_admin() - message logs", function()
    local default_prefix = conf.prefix
    local mock_prefix  = "servroot_2"
    local idx_filename = mock_prefix .. "/gui_config/kconfig.js"
    local usr_path = "servroot"
    local usr_interface_dir = "gui2"
    local usr_interface_path = usr_path .. "/" .. usr_interface_dir

    setup(function()
      conf.prefix = mock_prefix
      helpers.execute("rm -f " .. idx_filename)

      if not pl_path.exists(usr_interface_path) then
        assert(pl_path.mkdir(usr_interface_path))
      end
    end)

    teardown(function()
      if pl_path.isfile(idx_filename) then
        pl_file.delete(idx_filename)
      end

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

      local err_1 = "Could not create directory servroot_2/gui_config. "
                 .. "Ensure that the Kong CLI user has permissions to "
                 .. "create this directory."

      local err_2 = "ln: failed to create symbolic link 'servroot_2/gui2': "
                 .. "No such file or directory\n"

      local err_3 = "Could not write file servroot_2/gui_config/kconfig.js. "
                 .. "Ensure that the Kong CLI user has permissions to write "
                 .. "to this directory"

      local count = 1

      local function is_correct(state, arguments)
        return function(value)
          local str = string.match(value, arguments[1])  or
                      string.match(value, arguments[2])  or
                      string.match(value, arguments[3])

          assert.same(value, str)

          if count == #arguments then
            return true
          end

          count = count + 1
        end
      end

      assert:register("matcher", "correct", is_correct)

      ee.prepare_interface(usr_path, usr_interface_dir, "gui_config", {}, conf)
      assert.spy(spy_log).was_called(3)
      assert.spy(spy_log).was_called_with(match.is_correct(err_1, err_2, err_3))
    end)
  end)
end)
