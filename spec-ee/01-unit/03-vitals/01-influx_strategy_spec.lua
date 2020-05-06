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

  describe("when hostname is not provided", function()
    it("group by hostname", function()
      local expected = "SELECT count(status) FROM kong_request" ..
      " WHERE time > now() - 3600s" ..
      " GROUP BY status_f, service"
      assert.are.same(expected, strategy.status_code_query(nil, "service", "3600", "minutes"))
    end)
  end)

  describe("when hostname is provided", function()
    it("group by interval", function()
      local expected = "SELECT count(status) FROM kong_request" ..
      " WHERE time > now() - 3600s and service='f25a1190-363c-4b1e-8202-b806631d6038'" ..
      " GROUP BY status_f,  time(60s)"
      assert.are.same(expected, strategy.status_code_query("f25a1190-363c-4b1e-8202-b806631d6038", "service", "3600", "minutes"))
    end)
  end)
end)


describe("resolve_entity_name", function()
  local strategy = require "kong.vitals.influxdb.strategy"

  describe("when entity is service", function()
    it("uses service name", function()
      local expected = { name = "myservice" }
      local entity = { name = "myservice" }
      assert.are.same(expected, strategy.resolve_entity_name(entity))
    end)
  end)

  describe("when entity is consumer", function()
    it("uses consumer name", function()
      local expected = { name = "myconsumer" }
      local entity = { username = "myconsumer" }
      assert.are.same(expected, strategy.resolve_entity_name(entity))
    end)
  end)

  describe("when entity is consumer with underscore", function()
    it("uses consumer name with empty app_id and app_name", function()
      local expected = { name = "my_consumer", app_id = "", app_name = "" }
      local entity = { username = "my_consumer" }
      assert.are.same(expected, strategy.resolve_entity_name(entity))
    end)
  end)

  describe("when entity is application", function()
    it("name is blank and adds app_id and app_name", function()
      local expected = { name = "", app_id = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69", app_name = "mycoolapp" }
      local entity = { username = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69_mycoolapp", type = 3 }
      assert.are.same(expected, strategy.resolve_entity_name(entity))
    end)
  end)

  describe("when entity is application and name has an underscore", function()
    it("name is blank and adds app_id and app_name", function()
      local expected = { name = "", app_id = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69", app_name = "my_cool_app" }
      local entity = { username = "60c29e1b-3794-4c83-ad8d-b756b4d9ca69_my_cool_app", type = 3 }
      assert.are.same(expected, strategy.resolve_entity_name(entity))
    end)
  end)
end)