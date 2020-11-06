-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

describe("status_code_query", function()
  local strategy = require "kong.vitals.prometheus.strategy"

  describe("when service and id is not provided", function()
    it("group by service id", function()
      local expected = "sum(kong_status_code) by (service, status_code)"
      assert.are.same(expected, strategy.status_code_query(nil, "service"))
    end)
  end)

  describe("when service id is provided", function()
    it("group by interval", function()
      local expected = "sum(kong_status_code{service='f25a1190-363c-4b1e-8202-b806631d6038'}) by (status_code)"
      assert.are.same(expected, strategy.status_code_query("f25a1190-363c-4b1e-8202-b806631d6038", "service"))
    end)
  end)
end)