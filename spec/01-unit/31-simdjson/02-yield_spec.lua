local orig_ngx_sleep = ngx.sleep


local spy_ngx_sleep
local simdjson


describe("[yield] ", function ()
  before_each(function()
    spy_ngx_sleep = spy.on(ngx, "sleep")
    simdjson = require("resty.simdjson")
  end)


  after_each(function()
    ngx.sleep = orig_ngx_sleep
    package.loaded["resty.simdjson"] = nil
    package.loaded["resty.simdjson.decoder"] = nil
    package.loaded["resty.simdjson.encoder"] = nil
  end)


  it("enabled when encoding", function()

    local parser = simdjson.new(true)
    assert(parser)

    local str = parser:encode({ str = string.rep("a", 2100) })

    parser:destroy()

    assert(str)
    assert(type(str) == "string")
    assert.spy(spy_ngx_sleep).was_called(1)
  end)


  it("disabled when encoding", function()

    local parser = simdjson.new(false)
    assert(parser)

    local str = parser:encode({ str = string.rep("a", 2100) })

    parser:destroy()

    assert(str)
    assert(type(str) == "string")
    assert.spy(spy_ngx_sleep).was_called(0)
  end)


  it("enabled when decoding", function()

    local a = {}
    for i = 1, 1000 do
      a[i] = i
    end

    local parser = simdjson.new(true)
    assert(parser)

    local obj = parser:decode("[" .. table.concat(a, ",") .. "]")

    parser:destroy()

    assert(obj)
    assert(type(obj) == "table")
    assert.spy(spy_ngx_sleep).was_called(1)
  end)


  it("disabled when decoding", function()

    local a = {}
    for i = 1, 1000 do
      a[i] = i
    end

    local parser = simdjson.new(false)
    assert(parser)

    local obj = parser:decode("[" .. table.concat(a, ",") .. "]")

    parser:destroy()

    assert(obj)
    assert(type(obj) == "table")
    assert.spy(spy_ngx_sleep).was_called(0)
  end)
end)
