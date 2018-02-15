local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local meta           = require "kong.enterprise_edition.meta"
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
    local mock_idx = [[
      <meta name="KONG:PORTAL_GUI_URI" content="{{PORTAL_GUI_URI}}" />
      <meta name="KONG:PORTAL_GUI_SSL_URI" content="{{PORTAL_GUI_SSL_URI}}" />
      <meta name="KONG:PORTAL_API_URI" content="{{PORTAL_API_URI}}" />
      <meta name="KONG:PORTAL_API_SSL_URI" content="{{PORTAL_API_SSL_URI}}" />
      <meta name="KONG:PORTAL_API_URI_ENDPOINT" content="{{PORTAL_API_URI_ENDPOINT}}" />
      <meta name="KONG:PORTAL_GUI_PORT" content="{{PORTAL_GUI_PORT}}" />
      <meta name="KONG:PORTAL_GUI_SSL_PORT" content="{{PORTAL_GUI_SSL_PORT}}" />
      <meta name="KONG:PORTAL_API_PORT" content="{{ADMIN_API_PORT}}" />
      <meta name="KONG:PORTAL_API_SSL_PORT" content="{{PORTAL_API_SSL_PORT}}" />
      <meta name="KONG:RBAC_ENFORCED" content="{{RBAC_ENFORCED}}" />
      <meta name="KONG:RBAC_HEADER" content="{{RBAC_HEADER}}" />
      <meta name="KONG:KONG_VERSION" content="{{KONG_VERSION}}" />
    ]]
  
    local mock_prefix  = "servroot"
    local idx_filename = mock_prefix .. "/portal/index.html"
    local tp_filename  = mock_prefix .. "/portal/index.html.tp-" ..
                         tostring(meta.versions.package)

    local conf = {
      prefix = mock_prefix,
      PORTAL_GUI_URI = '127.0.0.1:8003',
      PORTAL_GUI_SSL_URI = '127.0.0.1:8446',
      PORTAL_API_URI = '127.0.0.1:8004',
      PORTAL_API_SSL_URI = '127.0.0.1:8447',
      PORTAL_API_URI_ENDPOINT = '/portal',
      PORTAL_GUI_PORT = 8003,
      PORTAL_GUI_SSL_PORT = 8446,
      PORTAL_API_PORT = 8004,
      PORTAL_API_SSL_PORT = 8447,
      RBAC_ENFORCED = false,
      RBAC_HEADER = 'Kong-Admin-Token',
      KONG_VERSION = '0.12.1',
    }

    setup(function()
      helpers.prepare_prefix(mock_prefix)
  
      -- create a mock gui folder
      pl_path.mkdir(mock_prefix .. "/portal")
      assert(pl_path.isdir(mock_prefix))
  
      -- write a mock index.html
      pl_file.write(idx_filename, mock_idx)
      assert(not pl_path.isfile(tp_filename))
      assert(pl_path.isfile(idx_filename))
    end)
  
    teardown(function()
      if pl_path.isfile(tp_filename) then
        pl_file.delete(tp_filename)
      end
    end)
  
    it("inserts the appropriate values", function()
      ee.prepare_portal(conf)
  
      local gui_idx = pl_file.read(idx_filename)
      for conf_name, conf_value in ipairs(conf) do
        if not conf_name == "prefix" then
          assert.matches(
            '<meta name="KONG:' .. conf_name .. '" content="' .. conf_value .. '" />',
            gui_idx, nil, true)
        end
      end
    end)
  
    it("retains a template with the template placeholders", function()
      local gui_idx_tpl = pl_file.read(tp_filename)
      for conf_name, conf_value in ipairs(conf) do
        if not conf_name == "prefix" then
          assert.matches(
            '<meta name="KONG:' .. conf_name .. '" content="{{' .. conf_name .. '}}" />',
            gui_idx_tpl, nil, true)
        end
      end
    end)
  
    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.PORTAL_GUI_URI = 'insecure.domain.com'
      new_conf.PORTAL_GUI_SSL_URI = 'domain.com'
      new_conf.PORTAL_API_URI = '127.0.0.1:8000'
      new_conf.PORTAL_GUI_URI = '127.0.0.1:8443'

      -- update template
      ee.prepare_admin(new_conf)

      -- test configuration values against template
      local gui_idx = pl_file.read(idx_filename)
      for conf_name, conf_value in ipairs(new_conf) do
        if not conf_name == "prefix" then
          assert.matches(
            '<meta name="KONG:' .. conf_name .. '" content="' .. conf_value .. '" />',
            gui_idx, nil, true)
        end
      end
    end)
  end)
end)
