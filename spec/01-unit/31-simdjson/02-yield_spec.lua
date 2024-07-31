describe("[enable yield] ", function ()
  local spy_ngx_sleep = spy.on(ngx, "sleep")
  local simdjson = require("resty.simdjson")

  it("when encoding", function()

    local parser = simdjson.new(true)
    assert(parser)

    local str = parser:encode({ str = string.rep("a", 2100) })

    parser:destroy()

    assert(str)
    assert(type(str) == "string")
    assert.spy(spy_ngx_sleep).was_called(1)
  end)


  it("when decoding", function()

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
    assert.spy(spy_ngx_sleep).was_called(2)
  end)
end)
