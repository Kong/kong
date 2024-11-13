local mp_rpc = require "kong.runloop.plugin_servers.mp_rpc"
local msgpack = require "MessagePack"
local cjson = require "cjson.safe"

local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack

describe("msgpack patched", function()
  it("visits service methods", function()
    local v = "\xff\x00\xcf"
    msgpack.set_string('binary')
    local result = msgpack.pack(v)
    msgpack.set_string('string_compat')
    local tests = {
        mp_rpc.must_fix["kong.request.get_raw_body"],
        mp_rpc.must_fix["kong.response.get_raw_body"],
        mp_rpc.must_fix["kong.service.response.get_raw_body"],
    }
    for _, test in ipairs(tests) do
        local packed = mp_pack(test(v))
        assert(result, packed)
        local unpacked = mp_unpack(packed)
        assert.same(v, unpacked)
    end
  end)
  
  it("unpack nil", function()  
    local tests = {
        {cjson.null},
        {ngx.null}
    }
    for _, test in ipairs(tests) do
        local packed = mp_pack(test)
        local unpacked = mp_unpack(packed)
        assert.same(nil, unpacked[1], "failed to reproduce null when unpack")
    end
  end)
end)