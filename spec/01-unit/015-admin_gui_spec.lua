local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"
local meta           = require "kong.enterprise_edition.meta"
local ee             = require "kong.enterprise_edition"

local pl_file = require "pl.file"
local pl_path = require "pl.path"

local exists = helpers.path.exists

describe("admin_gui", function()
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
end)

describe("prepare_prefix", function()
  local mock_idx = [[
    'ADMIN_API_URI': '{{ADMIN_API_URI}}',
    'ADMIN_API_PORT': '{{ADMIN_API_PORT}}',
    'ADMIN_API_SSL_PORT': '{{ADMIN_API_SSL_PORT}}',
    'RBAC_ENFORCED': '{{RBAC_ENFORCED}}',
    'RBAC_HEADER': '{{RBAC_HEADER}}',
    'KONG_VERSION': '{{KONG_VERSION}}',
    'FEATURE_FLAGS': '{{FEATURE_FLAGS}}'
  ]]

  local mock_prefix  = "servroot"
  local idx_filename = mock_prefix .. "/gui/index.html"
  local tp_filename  = mock_prefix .. "/gui/index.html.tp-" ..
                       tostring(meta.versions.package)

  setup(function()
    helpers.prepare_prefix(mock_prefix)

    -- create a mock gui folder
    pl_path.mkdir(mock_prefix .. "/gui")

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
    -- prepare with some mock values
    local conf = assert(conf_loader(helpers.test_conf_path))

    ee.prepare_admin({
      prefix = mock_prefix,
      admin_listeners = {
        {
          ip = "0.0.0.0",
          port = 9001,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 9444,
          ssl = true,
        }
      },
      enforce_rbac = false,
      rbac_auth_header = "Kong-Admin-Token",
      admin_gui_flags = "{}",
      admin_api_uri = NONE
    })

    local gui_idx = pl_file.read(idx_filename)

    assert.matches("'ADMIN_API_URI': ''", gui_idx, nil, true)
    assert.matches("'ADMIN_API_PORT': '9001'", gui_idx, nil, true)
    assert.matches("'ADMIN_API_SSL_PORT': '9444'", gui_idx, nil, true)
    assert.matches("'RBAC_ENFORCED': 'false'", gui_idx, nil, true)
    assert.matches("'RBAC_HEADER': 'Kong-Admin-Token'", gui_idx, nil, true)
    assert.matches("'KONG_VERSION': '" .. tostring(meta.versions.package) ..
      "'", gui_idx, nil, true)
    assert.matches("'FEATURE_FLAGS': '" .. tostring(conf.admin_gui_flags) ..
      "'", gui_idx, nil, true)
  end)

  it("retains a template with the template placeholders", function()
    local gui_idx_tpl = pl_file.read(tp_filename)

    assert.matches("'ADMIN_API_URI': '{{ADMIN_API_URI}}'",
                   gui_idx_tpl, nil, true)
    assert.matches("'ADMIN_API_PORT': '{{ADMIN_API_PORT}}'",
                   gui_idx_tpl, nil, true)
    assert.matches("'ADMIN_API_SSL_PORT': '{{ADMIN_API_SSL_PORT}}'",
                  gui_idx_tpl, nil, true)
    assert.matches("'RBAC_ENFORCED': '{{RBAC_ENFORCED}}'",
                  gui_idx_tpl, nil, true)
    assert.matches("'RBAC_HEADER': '{{RBAC_HEADER}}'", gui_idx_tpl, nil, true)
    assert.matches("'KONG_VERSION': '{{KONG_VERSION}}'",
                  gui_idx_tpl, nil, true)
    assert.matches("'FEATURE_FLAGS': '{{FEATURE_FLAGS}}'",
                  gui_idx_tpl, nil, true)
  end)

  it("inserts new values when called again", function()
    -- prepare with some mock values
    ee.prepare_admin({
      prefix = mock_prefix,
      admin_listeners = {
        {
          ip = "0.0.0.0",
          port = 9002,
          ssl = false,
        },
        {
          ip = "0.0.0.0",
          port = 9445,
          ssl = true,
        }
      },
      enforce_rbac = true,
      rbac_auth_header = "Kong-Other-Token",
      admin_gui_flags = "{ HIDE_VITALS: true }",
      admin_api_uri = "another-one.com"
    })

    local gui_idx = pl_file.read(idx_filename)

    assert.matches("'ADMIN_API_URI': 'another-one.com'", gui_idx, nil, true)
    assert.matches("'ADMIN_API_PORT': '9002'", gui_idx, nil, true)
    assert.matches("'ADMIN_API_SSL_PORT': '9445'", gui_idx, nil, true)
    assert.matches("'RBAC_ENFORCED': 'true'", gui_idx, nil, true)
    assert.matches("'RBAC_HEADER': 'Kong-Other-Token'", gui_idx, nil, true)
    assert.matches("'FEATURE_FLAGS': '{ HIDE_VITALS: true }'",
                  gui_idx, nil, true)
    assert.matches("'KONG_VERSION': '".. tostring(meta.versions.package) .. "'",
                  gui_idx, nil, true)
  end)
end)
