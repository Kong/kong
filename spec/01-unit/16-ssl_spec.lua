local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local ssl = require "kong.cmd.utils.ssl"

describe("SSL Utils", function()

  setup(function()
    pcall(pl_dir.rmtree, "/tmp/ssl")
  end)

  it("should auto-generate an SSL certificate and key", function()
    assert(ssl.prepare_ssl_cert_and_key("/tmp"))
    assert(pl_path.exists("/tmp/ssl/kong-default.crt"))
    assert(pl_path.exists("/tmp/ssl/kong-default.key"))
  end)

  it("retrieve the default SSL certificate and key", function()
    local ssl_data, err = ssl.get_ssl_cert_and_key({}, "/tmp")
    assert.is_table(ssl_data)
    assert.is_nil(err)

    assert.is_string(ssl_data.ssl_cert)
    assert.is_string(ssl_data.ssl_cert_key)
  end)

end)