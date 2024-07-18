-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local nan = require "cjson".decode("NaN")
local tohex = require "resty.string".to_hex

describe("redis utils", function()

  it("convert_vector_to_bytes", function()
    local u = function(...)
      return tohex(require "kong.llm.vectordb.strategies.redis.utils".convert_vector_to_bytes(...))
    end

    assert.equal('cdcccc3dcdcc4c3e9a99993e', u({0.1, 0.2, 0.3}))

    local d = {}
    for i = 1, 1024 do d[i] = 1 end
    assert.equal(string.rep('0000803f', 1024), u(d))

    assert.equal('c2160100', u({1e-40}))
    assert.equal('c2160180', u({-1e-40}))

    -- Note: -NaN in python
    assert.equal('0000c0ff', u({nan}))
  end)
end)
