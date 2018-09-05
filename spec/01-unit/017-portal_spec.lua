local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local ee             = require "kong.enterprise_edition"

local pl_file = require "pl.file"
local pl_path = require "pl.path"

local exists = helpers.path.exists

describe("portal_api", function()
  local conf = assert(conf_loader(helpers.test_conf_path))

 it("auto-generates SSL certificate and key", function()
   assert(prefix_handler.gen_default_ssl_cert(conf, "portal_api"))
   assert(exists(conf.portal_api_ssl_cert_default))
   assert(exists(conf.portal_api_ssl_cert_key_default))
 end)

 it("does not re-generate if they already exist", function()
   assert(prefix_handler.gen_default_ssl_cert(conf, "portal_api"))
   local cer = helpers.file.read(conf.portal_api_ssl_cert_default)
   local key = helpers.file.read(conf.portal_api_ssl_cert_key_default)
   assert(prefix_handler.gen_default_ssl_cert(conf, "portal_api"))
   assert.equal(cer, helpers.file.read(conf.portal_api_ssl_cert_default))
   assert.equal(key, helpers.file.read(conf.portal_api_ssl_cert_key_default))
 end)

 it("generates a different SSL certificate and key from the RESTful API", function()
   assert(prefix_handler.gen_default_ssl_cert(conf, "portal_api"))
   local cer, key = {}, {}
   cer[1] = helpers.file.read(conf.portal_api_ssl_cert_default)
   key[1] = helpers.file.read(conf.portal_api_ssl_cert_key_default)
   assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
   cer[2] = helpers.file.read(conf.admin_ssl_cert_default)
   key[2] = helpers.file.read(conf.admin_ssl_cert_key_default)
   assert.not_equals(cer[1], cer[2])
   assert.not_equals(key[1], key[2])
 end)
end)

describe("portal_gui", function()
   local conf = assert(conf_loader(helpers.test_conf_path))

  it("auto-generates SSL certificate and key", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "portal_gui"))
    assert(exists(conf.portal_gui_ssl_cert_default))
    assert(exists(conf.portal_gui_ssl_cert_key_default))
  end)

  it("does not re-generate if they already exist", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "portal_gui"))
    local cer = helpers.file.read(conf.portal_gui_ssl_cert_default)
    local key = helpers.file.read(conf.portal_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "portal_gui"))
    assert.equal(cer, helpers.file.read(conf.portal_gui_ssl_cert_default))
    assert.equal(key, helpers.file.read(conf.portal_gui_ssl_cert_key_default))
  end)

  it("generates a different SSL certificate and key from the RESTful API", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "portal_gui"))
    local cer, key = {}, {}
    cer[1] = helpers.file.read(conf.portal_gui_ssl_cert_default)
    key[1] = helpers.file.read(conf.portal_gui_ssl_cert_key_default)
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin"))
    cer[2] = helpers.file.read(conf.admin_ssl_cert_default)
    key[2] = helpers.file.read(conf.admin_ssl_cert_key_default)
    assert.not_equals(cer[1], cer[2])
    assert.not_equals(key[1], key[2])
  end)

  describe("prepare_prefix", function()
    local mock_prefix  = "servroot"
    local idx_filename = mock_prefix .. "/portal/kconfig.js"

    local conf = {
      prefix = mock_prefix,
      portal_auth = 'basic-auth',
      portal_gui_url = nil,
      proxy_url = nil,
      portal_gui_listeners = {
        {
          ip = "0.0.0.0",
          port = 8003,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8446,
          ssl = true,
        },
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
      portal_api_listeners = {
        {
          ip = "0.0.0.0",
          port = 8004,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 8447,
          ssl = true,
        }
      },
      enforce_rbac = "off",
      rbac_auth_header = 'Kong-Admin-Token',
    }

    setup(function()
      helpers.execute("rm -f " .. idx_filename)
      ee.prepare_portal(conf)
      assert(pl_path.isdir(mock_prefix))
      assert(pl_path.isfile(idx_filename))
    end)

    teardown(function()
      if pl_path.isfile(idx_filename) then
        pl_file.delete(idx_filename)
      end
    end)

    it("inserts the appropriate values", function()
      local portal_idx = pl_file.read(idx_filename)

      assert.matches("'PORTAL_AUTH': 'basic-auth'", portal_idx, nil, true)
      assert.matches("'PORTAL_GUI_URL': ''", portal_idx, nil, true)
      assert.matches("'PORTAL_API_URL': ''", portal_idx, nil, true)
      assert.matches("'PORTAL_GUI_PORT': '8003'", portal_idx, nil, true)
      assert.matches("'PORTAL_GUI_SSL_PORT': '8446'", portal_idx, nil, true)
      assert.matches("'PORTAL_API_PORT': '8004'", portal_idx, nil, true)
      assert.matches("'PORTAL_API_SSL_PORT': '8447'", portal_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", portal_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", portal_idx, nil, true)
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.portal_gui_url = 'http://insecure.domain.com'
      new_conf.portal_api_url = 'http://127.0.0.1:8004'

      -- update template
      ee.prepare_portal(new_conf)
      local portal_idx = pl_file.read(idx_filename)

      -- test configuration values against template
      assert.matches("'PORTAL_GUI_URL': 'http://insecure.domain.com'", portal_idx, nil, true)
      assert.matches("'PORTAL_API_URL': 'http://127.0.0.1:8004'", portal_idx, nil, true)
      assert.matches("'PORTAL_GUI_PORT': '8003'", portal_idx, nil, true)
      assert.matches("'PORTAL_GUI_SSL_PORT': '8446'", portal_idx, nil, true)
      assert.matches("'PORTAL_API_PORT': '8004'", portal_idx, nil, true)
      assert.matches("'PORTAL_API_SSL_PORT': '8447'", portal_idx, nil, true)
      assert.matches("'RBAC_ENFORCED': 'false'", portal_idx, nil, true)
      assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", portal_idx, nil, true)
    end)
  end)
end)
