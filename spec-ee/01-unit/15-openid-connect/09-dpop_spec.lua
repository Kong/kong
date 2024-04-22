-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local dpop_test = require("kong.openid-connect.dpop").__TEST__
local normalize_dpop_url = dpop_test.normalize_dpop_url
local encode_timestamp = dpop_test.encode_timestamp
local decode_timestamp = dpop_test.decode_timestamp

describe("dpop unit test", function()
  describe("normalize_dpop_url()", function()
    it("should normalize the URL", function()
      local normalized_url = normalize_dpop_url("https://example.com:443/p%61%74h?query=1#section1")
      assert.same("https://example.com/path", normalized_url)
    end)

    it("should reject non-strings", function()
      local normalized_url, err = normalize_dpop_url({"https://example.com:443/p%61%74h?query=1#section1"})
      assert.is_nil(normalized_url)
      assert.truthy(err)

      normalized_url, err = normalize_dpop_url(nil)
      assert.is_nil(normalized_url)
      assert.truthy(err)
    end)
  end)

  describe("encode_timestamp() and decode_timestamp()", function()
    it("should encode into 5 bytes", function()
      local encoded = encode_timestamp(ngx.time())
      assert.same(5, #encoded)
    end)

    it("should decode to the original value", function()
      local now = ngx.time()
      local encoded = encode_timestamp(now)
      local decoded = decode_timestamp(encoded)
      assert.same(now, decoded)
    end)
  end)
end)