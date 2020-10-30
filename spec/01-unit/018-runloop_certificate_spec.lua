-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local certificate = require "kong.runloop.certificate"
local produce_wild_snis = certificate.produce_wild_snis


describe("kong.runloop.certificate", function()
  describe("produce_wild_snis", function()
    it("throws an error when arg is not a string", function()
      assert.has_error(function()
        produce_wild_snis()
      end, "sni must be a string")
    end)

    it("produces suffix wildcard SNI", function()
      local prefix, suffix = produce_wild_snis("domain.com")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs", function()
      local prefix, suffix = produce_wild_snis("www.domain.com")
      assert.equal("*.domain.com", prefix)
      assert.equal("www.domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs on sub-subnames", function()
      local prefix, suffix = produce_wild_snis("foo.www.domain.com")
      assert.equal("*.www.domain.com", prefix)
      assert.equal("foo.www.domain.*", suffix)
    end)

    it("does not produce wildcard SNIs when input is wildcard", function()
      local prefix, suffix = produce_wild_snis("*.domain.com")
      assert.equal("*.domain.com", prefix)
      assert.is_nil(suffix)

      prefix, suffix = produce_wild_snis("domain.*")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)
  end)
end)
