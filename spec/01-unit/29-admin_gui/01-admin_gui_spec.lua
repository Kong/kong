-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local conf_loader    = require "kong.conf_loader"
local prefix_handler = require "kong.cmd.utils.prefix_handler"

local helpers        = require "spec.helpers"

describe("admin_gui", function()
  local conf = assert(conf_loader(helpers.test_conf_path))

  it("auto-generates SSL certificate and key", function()
    assert(prefix_handler.gen_default_ssl_cert(conf, "admin_gui"))
    assert(helpers.path.exists(conf.admin_gui_ssl_cert_default))
    assert(helpers.path.exists(conf.admin_gui_ssl_cert_key_default))
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
