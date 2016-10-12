describe("globalpatches", function()
  describe("assert", function()
    it("does not errors zhen arg #3 is not a number", function()
      -- if not patched, this would throw:
      -- luassert/assert.lua:155: attempt to perform arithmetic on a string value
      assert.error_matches(function()
        assert(false, "some error", "some return value")
      end, "some error", nil, true)
    end)
  end)
end)
