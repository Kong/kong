-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

--
-- imports
--

local utils = require("kong.ai.semantic_cache.utils")

--
-- private vars
--

local uuid_regexp = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
local test_uuid = "ac82f632-1475-449a-a670-8e36a3df2014"

--
-- tests
--

describe("[utils]", function()
  describe("generators:", function()
    it("generates full index names", function()
      assert.is.equal("idx:test_index1_vss", utils.full_index_name("test_index1"))
      assert.is.equal("idx:test_index2_vss", utils.full_index_name("test_index2"))
      assert.is.equal("idx:test_index3_vss", utils.full_index_name("test_index3"))
    end)

    it("generates cache keys", function()
      assert.is.truthy(ngx.re.find(utils.cache_key("test_index1"), "test_index1:" .. uuid_regexp .. "$"))
      assert.is.truthy(ngx.re.find(utils.cache_key("test_index2"), "test_index2:" .. uuid_regexp .. "$"))
      assert.is.truthy(ngx.re.find(utils.cache_key("test_index3"), "test_index3:" .. uuid_regexp .. "$"))
    end)

    it("can be optionally given an existing uuid", function()
      assert.equal("test_index1:" .. test_uuid, utils.cache_key("test_index1", test_uuid))
      assert.equal("test_index2:" .. test_uuid, utils.cache_key("test_index2", test_uuid))
      assert.equal("test_index3:" .. test_uuid, utils.cache_key("test_index3", test_uuid))
    end)
  end)
end)
