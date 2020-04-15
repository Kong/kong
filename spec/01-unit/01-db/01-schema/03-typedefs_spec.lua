local Schema = require "kong.db.schema"
local typedefs = require("kong.db.schema.typedefs")
local openssl_pkey = require "resty.openssl.pkey"
local openssl_x509 = require "resty.openssl.x509"
local ssl_fixtures = require "spec.fixtures.ssl"


describe("typedefs", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local a_blank_uuid = "00000000-0000-0000-0000-000000000000"

  it("features sni typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.sni }
      }
    })
    assert.truthy(Test:validate({ f = "example.com" }))
    assert.truthy(Test:validate({ f = "9foo.te-st.bar.test" }))
    assert.falsy(Test:validate({ f = "127.0.0.1" }))
    assert.falsy(Test:validate({ f = "example.com:80" }))
    assert.falsy(Test:validate({ f = "[::1]" }))
  end)

  it("features certificate typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.certificate }
      }
    })
    assert.truthy(Test:validate({ f = ssl_fixtures.cert }))
    do
      local key = openssl_pkey.new { bits = 2048 }
      local crt = openssl_x509.new()
      crt:set_pubkey(key)
      crt:sign(key)
      assert.truthy(Test:validate({ f = crt:to_PEM() }))
    end
    do
      local ok, err = Test:validate({ f = 42 })
      assert.falsy(ok)
      assert.matches("expected a string", err.f)
    end
    do
      local ok, err = Test:validate({ f = "not a certificate" })
      assert.falsy(ok)
      assert.matches("invalid certificate", err.f)
    end
    do
      local ok, err = Test:validate({ f = [[
-----BEGIN CERTIFICATE-----
-----END CERTIFICATE-----
]]})
      assert.falsy(ok)
      assert.matches("invalid certificate", err.f)
    end
  end)

  it("features key typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.key }
      }
    })
    assert.truthy(Test:validate({ f = ssl_fixtures.key }))
    local tmpkey = openssl_pkey.new { bits = 2048 }
    assert.truthy(Test:validate({ f = tmpkey:to_PEM("private") }))
    assert.truthy(Test:validate({ f = tmpkey:to_PEM("public") }))
    do
      local ok, err = Test:validate({ f = 42 })
      assert.falsy(ok)
      assert.matches("expected a string", err.f)
    end
    do
      local ok, err = Test:validate({ f = "not a key" })
      assert.falsy(ok)
      assert.matches("invalid key", err.f)
    end
    do
      local ok, err = Test:validate({ f = [[
-----BEGIN PRIVATE KEY-----
-----END PRIVATE KEY-----
]]})
      assert.falsy(ok)
      assert.matches("invalid key", err.f)
    end
  end)

  it("features port typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.port }
      }
    })
    assert.truthy(Test:validate({ f = 1024 }))
    assert.truthy(Test:validate({ f = 65535 }))
    assert.truthy(Test:validate({ f = 65535.0 }))
    assert.falsy(Test:validate({ f = "get" }))
    assert.falsy(Test:validate({ f = 65536 }))
    assert.falsy(Test:validate({ f = 65536.1 }))
  end)

  it("features protocol typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.protocol }
      }
    })
    assert.truthy(Test:validate({ f = "http" }))
    assert.truthy(Test:validate({ f = "https" }))
    assert.falsy(Test:validate({ f = "ftp" }))
    assert.falsy(Test:validate({ f = {} }))
  end)

  it("features timeout typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.timeout }
      }
    })
    assert.truthy(Test:validate({ f = 120 }))
    assert.truthy(Test:validate({ f = 0 }))
    assert.falsy(Test:validate({ f = -1 }))
    assert.falsy(Test:validate({ f = math.huge }))
  end)

  it("features uuid typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.uuid }
      }
    })
    assert.truthy(Test:validate({ f = a_valid_uuid }))
    assert.truthy(Test:validate({ f = a_blank_uuid }))
    assert.falsy(Test:validate({ f = "hello" }))
    assert.falsy(Test:validate({ f = 123 }))
  end)

  it("features http_method typedef", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.http_method }
      }
    })
    assert.truthy(Test:validate({ f = "GET" }))
    assert.truthy(Test:validate({ f = "FOOBAR" }))
    assert.falsy(Test:validate({ f = "get" }))
    assert.falsy(Test:validate({ f = 123 }))
  end)

  it("allows typedefs to be customized", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.timeout { default = 120 } }
      }
    })
    local data = Test:process_auto_fields({})
    assert.truthy(Test:validate(data))
    assert.same(data.f, 120)

    data = Test:process_auto_fields({ f = 900 })
    assert.truthy(Test:validate(data))
    assert.same(data.f, 900)
  end)

  it("supports function-call syntax", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.uuid() }
      }
    })
    assert.truthy(Test:validate({ f = a_valid_uuid }))
    assert.truthy(Test:validate({ f = a_blank_uuid }))
    assert.falsy(Test:validate({ f = "hello" }))
    assert.falsy(Test:validate({ f = 123 }))
  end)

  it("headers rejects 'host' but accepts 'host' substring", function()
    local Test = Schema.new({
      fields = {
        { f = typedefs.headers() }
      }
    })
    assert.falsy(Test:validate({ f = { ["host"]  = { "example.com" } } }))
    assert.truthy(Test:validate({ f = { ["hostname"]  = { "example.com" } } }))
  end)

  it("allows overriding typedefs with boolean false", function()
    local uuid = typedefs.uuid()
    assert.equal(true, uuid.auto)
    local uuid2 = typedefs.uuid({
      auto = false,
    })
    assert.equal(false, uuid2.auto)
 end)

end)
