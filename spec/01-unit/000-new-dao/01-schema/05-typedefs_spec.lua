local Schema = require "kong.db.schema"
local typedefs = require("kong.db.schema.typedefs")


describe("typedefs", function()
  local a_valid_uuid = "cbb297c0-a956-486d-ad1d-f9b42df9465a"
  local a_blank_uuid = "00000000-0000-0000-0000-000000000000"
 
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


end)
