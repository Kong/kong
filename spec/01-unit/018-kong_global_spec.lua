local kong = require "kong.kong"


describe("_G.kong", function()
  it(".version", function()
    assert.matches("%d+%.%d+%.%d+", kong.version)
  end)

  it(".version_num", function()
    assert.equal(13000, kong.version_num)
  end)

  it("has latest sdk preloaded", function()
    assert.has_no_error(function()
      kong.request.get_thing()
    end)
  end)


  describe(".swap_sdk()", function()
    assert.equal("hello v1", kong.request.get_thing())

    kong.swap_sdk(0) -- swap to version 0 (done by core for a given needy plugin)

    assert.equal("hello v0", kong.request.get_thing())
  end)


  describe("SDK", function()
    describe(".request", function()
      -- still not sure if we will test the SDK in busted (unlikely)
    end)
  end)
end)
