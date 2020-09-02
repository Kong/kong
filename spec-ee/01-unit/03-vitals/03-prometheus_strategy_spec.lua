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