-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local mp_rpc = require "kong.runloop.plugin_servers.rpc.mp_rpc".new()
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
