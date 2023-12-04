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
      local prefix, suffix = produce_wild_snis("domain.test")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs", function()
      local prefix, suffix = produce_wild_snis("www.domain.test")
      assert.equal("*.domain.test", prefix)
      assert.equal("www.domain.*", suffix)
    end)

    it("produces prefix and suffix wildcard SNIs on sub-subnames", function()
      local prefix, suffix = produce_wild_snis("foo.www.domain.test")
      assert.equal("*.www.domain.test", prefix)
      assert.equal("foo.www.domain.*", suffix)
    end)

    it("does not produce wildcard SNIs when input is wildcard", function()
      local prefix, suffix = produce_wild_snis("*.domain.test")
      assert.equal("*.domain.test", prefix)
      assert.is_nil(suffix)

      prefix, suffix = produce_wild_snis("domain.*")
      assert.is_nil(prefix)
      assert.equal("domain.*", suffix)
    end)
  end)
end)
