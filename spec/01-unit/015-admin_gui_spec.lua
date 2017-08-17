local helpers        = require "spec.helpers"
local prefix_handler = require "kong.cmd.utils.prefix_handler"
local conf_loader    = require "kong.conf_loader"

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
    <meta name="KONG:ADMIN_API_PORT" content="{{ADMIN_API_PORT}}" />
    <meta name="KONG:ADMIN_API_SSL_PORT" content="{{ADMIN_API_SSL_PORT}}" />
    <meta name="KONG:RBAC_ENFORCED" content="{{RBAC_ENFORCED}}" />
    <meta name="KONG:RBAC_HEADER" content="{{RBAC_HEADER}}" />
]]

  local mock_prefix = "servroot"

  setup(function()
    helpers.prepare_prefix(mock_prefix)

    -- create a mock gui folder
    pl_path.mkdir(mock_prefix .. "/gui")

    assert(pl_path.isdir(mock_prefix))

    -- write a mock index.html
    pl_file.write(mock_prefix .. "/gui/index.html", mock_idx)
    assert(not pl_path.isfile(mock_prefix .. "/gui/index.html.tp"))
    assert(pl_path.isfile(mock_prefix .. "/gui/index.html"))
  end)

  teardown(function()
    if pl_path.isfile(mock_prefix .. "/gui/index.html.tp") then
      pl_file.delete(mock_prefix .. "/gui/index.html.tp")
    end
  end)

  it("inserts the appropriate values", function()
    -- prepare with some mock values
    prefix_handler.prepare_admin({
      prefix = mock_prefix,
      admin_port = 9001,
      admin_ssl_port = 9444,
      enforce_rbac = false,
      rbac_auth_header = "Kong-Admin-Token",
    })

    local gui_idx = pl_file.read(mock_prefix .. "/gui/index.html")

    assert.matches('<meta name="KONG:ADMIN_API_PORT" content="9001" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:ADMIN_API_SSL_PORT" content="9444" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:RBAC_ENFORCED" content="false" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:RBAC_HEADER" content="Kong-Admin-Token" />',
                   gui_idx, nil, true)
  end)

  it("retains a template with the template placeholders", function()
    local gui_idx_tpl = pl_file.read(mock_prefix .. "/gui/index.html.tp")

    assert.matches('<meta name="KONG:ADMIN_API_PORT" content="{{ADMIN_API_PORT}}" />',
                   gui_idx_tpl, nil, true)
    assert.matches('<meta name="KONG:ADMIN_API_SSL_PORT" content="{{ADMIN_API_SSL_PORT}}" />',
                   gui_idx_tpl, nil, true)
    assert.matches('<meta name="KONG:RBAC_ENFORCED" content="{{RBAC_ENFORCED}}" />',
                   gui_idx_tpl, nil, true)
    assert.matches('<meta name="KONG:RBAC_HEADER" content="{{RBAC_HEADER}}" />',
                   gui_idx_tpl, nil, true)
  end)

  it("inserts new values when called again", function()
    -- prepare with some mock values
    prefix_handler.prepare_admin({
      prefix = mock_prefix,
      admin_port = 9002,
      admin_ssl_port = 9445,
      enforce_rbac = true,
      rbac_auth_header = "Kong-Other-Token",
    })

    local gui_idx = pl_file.read(mock_prefix .. "/gui/index.html")

    assert.matches('<meta name="KONG:ADMIN_API_PORT" content="9002" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:ADMIN_API_SSL_PORT" content="9445" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:RBAC_ENFORCED" content="true" />',
                   gui_idx, nil, true)
    assert.matches('<meta name="KONG:RBAC_HEADER" content="Kong-Other-Token" />',
                   gui_idx, nil, true)
  end)
end)
