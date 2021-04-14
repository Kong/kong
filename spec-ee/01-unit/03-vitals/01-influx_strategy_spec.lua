-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("authorization_headers", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("given user and password nil", function()
    it("creates empty table", function()
      assert.are.same({}, strategy.authorization_headers(nil, nil))
    end)
  end)

  describe("given user and password", function()
    it("creates table with Authorization header", function()
      local expected = { ["Authorization"] = "Basic a29uZzprb25n" }
      assert.are.same(expected, strategy.authorization_headers("kong", "kong"))
    end)
  end)
end)

describe("prepend_protocol", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("when tsdb_address doesn't have protocol", function()
    it("prepends http", function()
      assert.are.same("http://teddy.bear", strategy.prepend_protocol("teddy.bear"))
    end)
  end)

  describe("when tsdb_address has protocol", function()
    it("keeps the original address", function()
      assert.are.same("https://safe.bear", strategy.prepend_protocol("https://safe.bear"))
    end)
  end)
end)
