require "kong.runloop.plugin_servers.mp_rpc"
local msgpack = require "MessagePack"
local cjson = require "cjson.safe"

local mp_pack = msgpack.pack
local mp_unpack = msgpack.unpack

describe("msgpack patched", function()
  it("visits service methods", function()
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
