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


describe("latency_query", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("when hostname is not provided", function()
    it("group by hostname", function()
      local expected = "SELECT MAX(proxy_latency), MIN(proxy_latency)," ..
      " MEAN(proxy_latency), MAX(request_latency), MIN(request_latency)," ..
      " MEAN(request_latency) FROM kong_request" ..
      " WHERE time > now() - 3600s" ..
      " GROUP BY hostname"
      assert.are.same(expected, strategy.latency_query(nil, "3600", "minutes"))
    end)
  end)

  describe("when hostname is provided", function()
    it("group by interval", function()
      local expected = "SELECT MAX(proxy_latency), MIN(proxy_latency)," ..
      " MEAN(proxy_latency), MAX(request_latency), MIN(request_latency)," ..
      " MEAN(request_latency) FROM kong_request" ..
      " WHERE time > now() - 3600s AND hostname='my_hostname'" ..
      " GROUP BY time(60s)"
      assert.are.same(expected, strategy.latency_query("my_hostname", "3600", "minutes"))
    end)
  end)
end)


describe("status_code_query", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("when service id is not provided", function()
    it("group by service id", function()
      local expected = "SELECT count(status) FROM kong_request" ..
      " WHERE time > now() - 3600s" ..
      " GROUP BY status_f, service"
      assert.are.same(expected, strategy.status_code_query(nil, "service", "3600", "minutes"))
    end)
  end)

  describe("when service id is provided", function()
    it("group by interval", function()
      local expected = "SELECT count(status) FROM kong_request" ..
      " WHERE time > now() - 3600s and service='f25a1190-363c-4b1e-8202-b806631d6038'" ..
      " GROUP BY status_f,  time(60s)"
      assert.are.same(expected, strategy.status_code_query("f25a1190-363c-4b1e-8202-b806631d6038", "service", "3600", "minutes"))
    end)
  end)
end)
