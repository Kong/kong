local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local ee             = require "kong.enterprise_edition"
local meta           = require "kong.enterprise_edition.meta"
local singletons     = require "kong.singletons"
local ws_helper      = require "kong.workspaces.helper"

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

  describe("prepare_portal", function()
    local index_conf
    local snapshot

    before_each(function()
      snapshot = assert:snapshot()
    end)

    after_each(function()
      snapshot:revert()
    end)

    local conf = {
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
      portal_gui_use_subdomains = false,
    }

    it("inserts the appropriate values with empty config", function()
      stub(ws_helper, "get_workspace").returns({
        name = "default"
      })

      singletons.configuration = {
        portal_auth = "basic-auth",
      }

      index_conf = ee.prepare_portal({
        workspace = {
          name = "default",
        },
      }, conf)

      assert.same({
        PORTAL_IS_AUTHENTICATED = 'false',
        PORTAL_API_URL = "",
        PORTAL_AUTH = "basic-auth",
        PORTAL_API_PORT = "8004",
        PORTAL_API_SSL_PORT = "8447",
        PORTAL_GUI_URL = "",
        PORTAL_GUI_PORT = "8003",
        PORTAL_GUI_SSL_PORT = "8446",
        PORTAL_GUI_USE_SUBDOMAINS = 'false',
        RBAC_ENFORCED = 'false',
        RBAC_HEADER = "Kong-Admin-Token",
        KONG_VERSION = tostring(meta.versions.package),
        WORKSPACE = 'default',
      }, index_conf)
    end)

    it("inserts the appropriate values with different workspace name", function()
      stub(ws_helper, "get_workspace").returns({
        name = "gruce"
      })

      index_conf = ee.prepare_portal({}, conf)

      assert.same({
        PORTAL_IS_AUTHENTICATED = 'false',
        PORTAL_API_URL = "",
        PORTAL_AUTH = "basic-auth",
        PORTAL_API_PORT = "8004",
        PORTAL_API_SSL_PORT = "8447",
        PORTAL_GUI_URL = "",
        PORTAL_GUI_PORT = "8003",
        PORTAL_GUI_SSL_PORT = "8446",
        PORTAL_GUI_USE_SUBDOMAINS = 'false',
        RBAC_ENFORCED = 'false',
        RBAC_HEADER = "Kong-Admin-Token",
        KONG_VERSION = tostring(meta.versions.package),
        WORKSPACE = 'gruce'
      }, index_conf)
    end)

    it("inserts the appropriate values with different portal auth type", function()
      stub(ws_helper, "get_workspace").returns({
        config = {
          portal_auth = "key-auth",
        },
        name = "default"
      })

      index_conf = ee.prepare_portal({
        developer = {}
      }, conf)

      assert.same({
        PORTAL_IS_AUTHENTICATED = 'true',
        PORTAL_API_URL = "",
        PORTAL_AUTH = "key-auth",
        PORTAL_API_PORT = "8004",
        PORTAL_API_SSL_PORT = "8447",
        PORTAL_GUI_URL = "",
        PORTAL_GUI_PORT = "8003",
        PORTAL_GUI_SSL_PORT = "8446",
        PORTAL_GUI_USE_SUBDOMAINS = 'false',
        RBAC_ENFORCED = 'false',
        RBAC_HEADER = "Kong-Admin-Token",
        KONG_VERSION = tostring(meta.versions.package),
        WORKSPACE = 'default'
      }, index_conf)
    end)
  end)
end)
