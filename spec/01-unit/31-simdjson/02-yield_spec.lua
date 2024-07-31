local orig_ngx_sleep = ngx.sleep


local spy_ngx_sleep
local simdjson
local test_obj
local test_str


describe("[yield] ", function ()
  lazy_setup(function()
    test_obj = { str = string.rep("a", 2100), }

    local arr = {}
    for i = 1, 1000 do
      arr[i] = i
    end

    test_str = "[" .. table.concat(arr, ",") .. "]"
  end)


  before_each(function()
    spy_ngx_sleep = spy.on(ngx, "sleep")
    simdjson = require("resty.simdjson")
  end)


  after_each(function()
    ngx.sleep = orig_ngx_sleep  -- luacheck: ignore
    package.loaded["resty.simdjson"] = nil
    package.loaded["resty.simdjson.decoder"] = nil
    package.loaded["resty.simdjson.encoder"] = nil
  end)


  it("enabled when encoding", function()

    local parser = simdjson.new(true)
    assert(parser)

    local str = parser:encode(test_obj)

    parser:destroy()

    assert(str)
    assert(type(str) == "string")
    assert.spy(spy_ngx_sleep).was_called(1)       -- yield once
    assert.spy(spy_ngx_sleep).was_called_with(0)  -- yield 0ms
  end)


  it("disabled when encoding", function()

    local parser = simdjson.new(false)
    assert(parser)

    local str = parser:encode(test_obj)

    parser:destroy()

    assert(str)
    assert(type(str) == "string")
    assert.spy(spy_ngx_sleep).was_called(0)
  end)


  it("enabled when decoding", function()

    local parser = simdjson.new(true)
    assert(parser)

    local obj = parser:decode(test_str)

    parser:destroy()

    assert(obj)
    assert(type(obj) == "table")
    assert.spy(spy_ngx_sleep).was_called(1)       -- yield once
    assert.spy(spy_ngx_sleep).was_called_with(0)  -- yield 0ms
  end)


  it("disabled when decoding", function()

    local parser = simdjson.new(false)
    assert(parser)

    local obj = parser:decode(test_str)

    parser:destroy()

    assert(obj)
    assert(type(obj) == "table")
    assert.spy(spy_ngx_sleep).was_called(0)
  end)
end)
