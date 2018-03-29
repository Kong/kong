local meta = require "kong.meta"


describe("Public API", function()
  it("returns the most recent version", function()
    local kong = require "kong.public"
    assert.equal("1.0.1", kong._API_VERSION)
    assert.equal(10001,   kong._API_VERSION_NUM)


    local version_num = tonumber(string.format("%02u%02u%02u",
                                               meta._VERSION_TABLE.major,
                                               meta._VERSION_TABLE.minor,
                                               meta._VERSION_TABLE.patch))

    assert.equal(meta._VERSION, kong._VERSION)
    assert.equal(version_num,   kong._VERSION_NUM)
  end)

  it("returns the most recent 1.x.x version", function()
    local kong = require "kong.public".v("1")
    assert.equal("1.0.1", kong._API_VERSION)

    local kong = require "kong.public".v(1)
    assert.equal(10001,   kong._API_VERSION_NUM)

    local kong = require "kong.public".v("1.0")
    assert.equal("1.0.1", kong._API_VERSION)

    local kong = require "kong.public".v(1, 0)
    assert.equal(10001,   kong._API_VERSION_NUM)
  end)

  it("returns requested version", function()
    local kong = require "kong.public".v("1.0.0")
    assert.equal("1.0.0", kong._API_VERSION)
    assert.equal(10000,   kong._API_VERSION_NUM)
  end)


  it("returns the most recent version for specific api", function()
    local kong = require "kong.public"
    assert.equal("1.0.1", kong.cache._VERSION)
    assert.equal(10001,   kong.cache._VERSION_NUM)
    assert.equal("1.0.0", kong.configuration._VERSION)
    assert.equal(10000,   kong.configuration._VERSION_NUM)
  end)


  it("returns requested version for specific api", function()
    local kong = require "kong.public"
    assert.equal("1.0.0", kong.cache.v("1.0.0")._VERSION)
    assert.equal(10000,   kong.cache.v(1, 0, 0)._VERSION_NUM)
    assert.equal("1.0.0", kong.configuration._VERSION)
    assert.equal(10000,   kong.configuration._VERSION_NUM)
  end)
end)

