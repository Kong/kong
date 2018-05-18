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
      <meta name="KONG:PORTAL_AUTH" content="{{PORTAL_AUTH}}" />
      <meta name="KONG:PORTAL_GUI_URL" content="{{PORTAL_GUI_URL}}" />
      <meta name="KONG:PROXY_URL" content="{{PROXY_URL}}" />
      <meta name="KONG:PORTAL_GUI_PORT" content="{{PORTAL_GUI_PORT}}" />
      <meta name="KONG:PORTAL_GUI_SSL_PORT" content="{{PORTAL_GUI_SSL_PORT}}" />
      <meta name="KONG:PORTAL_API_PORT" content="{{PORTAL_API_PORT}}" />
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
      enforce_rbac = false,
      rbac_auth_header = 'Kong-Admin-Token',
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
      if pl_path.isfile(idx_filename) then
        pl_file.delete(idx_filename)
      end
    end)

    it("inserts the appropriate values", function()
      ee.prepare_portal(conf)
      local portal_idx = pl_file.read(idx_filename)

      assert.matches('<meta name="KONG:PORTAL_AUTH" content="basic-auth" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_URL" content="" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PROXY_URL" content="" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_PORT" content="8003" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_SSL_PORT" content="8446" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_PORT" content="8000" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_SSL_PORT" content="8443" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:RBAC_ENFORCED" content="false" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:RBAC_HEADER" content="Kong-Admin-Token" />', portal_idx, nil, true)
    end)

    it("retains a template with the template placeholders", function()
      local gui_idx_tpl = pl_file.read(tp_filename)

      assert.matches('<meta name="KONG:PORTAL_AUTH" content="{{PORTAL_AUTH}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_URL" content="{{PORTAL_GUI_URL}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PROXY_URL" content="{{PROXY_URL}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_PORT" content="{{PORTAL_GUI_PORT}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_SSL_PORT" content="{{PORTAL_GUI_SSL_PORT}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_PORT" content="{{PORTAL_API_PORT}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_SSL_PORT" content="{{PORTAL_API_SSL_PORT}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:RBAC_ENFORCED" content="{{RBAC_ENFORCED}}" />', gui_idx_tpl, nil, true)
      assert.matches('<meta name="KONG:RBAC_HEADER" content="{{RBAC_HEADER}}" />', gui_idx_tpl, nil, true)
    end)

    it("inserts new values when called again", function()
      local new_conf = conf

      -- change configuration values
      new_conf.portal_gui_url = 'http://insecure.domain.com'
      new_conf.proxy_url = 'http://127.0.0.1:8000'

      -- update template
      ee.prepare_portal(new_conf)
      local portal_idx = pl_file.read(idx_filename)

      -- test configuration values against template
      assert.matches('<meta name="KONG:PORTAL_GUI_URL" content="http://insecure.domain.com" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PROXY_URL" content="http://127.0.0.1:8000" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_PORT" content="8003" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_GUI_SSL_PORT" content="8446" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_PORT" content="8000" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:PORTAL_API_SSL_PORT" content="8443" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:RBAC_ENFORCED" content="false" />', portal_idx, nil, true)
      assert.matches('<meta name="KONG:RBAC_HEADER" content="Kong-Admin-Token" />', portal_idx, nil, true)
    end)
  end)
end)
