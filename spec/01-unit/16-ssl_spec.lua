local helpers = require "spec.helpers"
local ssl = require "kong.cmd.utils.ssl"

describe("SSL utils", function()
  local exists = helpers.path.exists
  local join = helpers.path.join
  setup(function()
    helpers.dir.makepath("ssl_tmp")
  end)
  teardown(function()
    pcall(helpers.dir.rmtree, "ssl_tmp")
  end)

  it("should auto-generate an SSL certificate and key", function()
    assert(ssl.prepare_ssl_cert_and_key("ssl_tmp"))
    assert(exists(join("ssl_tmp", "ssl", "kong-default.crt")))
    assert(exists(join("ssl_tmp", "ssl", "kong-default.key")))
  end)

  it("retrieve the default SSL certificate and key", function()
    local ssl_data = assert(ssl.get_ssl_cert_and_key({}, "ssl_tmp"))
    assert.is_table(ssl_data)
    assert.is_string(ssl_data.ssl_cert)
    assert.is_string(ssl_data.ssl_cert_key)
  end)
end)
