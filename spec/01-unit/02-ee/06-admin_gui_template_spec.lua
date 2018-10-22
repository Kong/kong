local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local ee             = require "kong.enterprise_edition"

local pl_file = require "pl.file"
local pl_path = require "pl.path"

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
    local idx_filename = mock_prefix .. "/gui/kconfig.js"

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
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.admin_api_uri = 'http://localhost:8001'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"

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
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", admin_idx, nil, true)
    end)
  end)

  describe("prepare_admin() - not proxied", function()
    local mock_prefix  = "servroot"
    local idx_filename = mock_prefix .. "/gui/kconfig.js"

    local conf = {
      prefix = mock_prefix,
      admin_gui_auth = nil,
      admin_gui_url = "http://0.0.0.0:8002",
      proxy_url = "http://0.0.0.0:8000",
      admin_api_uri = "0.0.0.0:8001",
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
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.admin_gui_url = 'http://admin-test.example.com'
      new_conf.proxy_url = 'http://127.0.0.1:8000'
      new_conf.admin_gui_flags = "{ HIDE_VITALS: true }"

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
      assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'", admin_idx, nil, true)
    end)
  end)
end)
