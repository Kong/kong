local helpers = require "spec.helpers"
local cjson = require "cjson"

local UDP_PORT = 20000

describe("Plugin: loggly (log)", function()
  local client
  setup(function()
    local _, db, dao = helpers.get_db_utils()

    local api1 = assert(dao.apis:insert {
      name         = "api-1",
      hosts        = { "logging.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api2 = assert(dao.apis:insert {
      name         = "api-2",
      hosts        = { "logging1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api3 = assert(dao.apis:insert {
      name         = "api-3",
      hosts        = { "logging2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api4 = assert(dao.apis:insert {
      name         = "api-4",
      hosts        = { "logging3.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(db.plugins:insert {
      api = { id = api1.id },
      name   = "loggly",
      config = {
        host                = "127.0.0.1",
        port                = UDP_PORT,
        key                 = "123456789",
        log_level           = "info",
        successful_severity = "warning"
      }
    })

  assert(db.plugins:insert {
      api = { id = api2.id },
      name   = "loggly",
      config = {
        host                = "127.0.0.1",
        port                = UDP_PORT,
        key                 = "123456789",
        log_level           = "debug",
        timeout             = 2000,
        successful_severity = "info",
      }
    })
  assert(db.plugins:insert {
      api = { id = api3.id },
      name   = "loggly",
      config = {
        host                   = "127.0.0.1",
        port                   = UDP_PORT,
        key                    = "123456789",
        log_level              = "crit",
        successful_severity    = "crit",
        client_errors_severity = "warning",
      }
    })
  assert(db.plugins:insert {
      api = { id = api4.id },
      name   = "loggly",
      config = {
        host = "127.0.0.1",
        port = UDP_PORT,
        key  = "123456789"
      }
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  -- Helper; performs a single http request and catches the udp log output.
  -- @param message the message table for the http client
  -- @param status expected status code from the request, defaults to 200 if omitted
  -- @return 2 values; 'pri' field (string) and the decoded json content (table)
  local function run(message, status)
    local thread = assert(helpers.udp_server(UDP_PORT))
    local response = assert(client:send(message))
    assert.res_status(status or 200, response)

    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    local pri = assert(res:match("^<(%d-)>"))
    local json = assert(res:match("{.*}"))

    return pri, cjson.decode(json)
  end

  it("logs to UDP when severity is warning and log level info", function()
    local pri, message = run({
      method = "GET",
      path = "/request",
      headers = {
        host = "logging.com"
      }
    })
    assert.equal("12", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity is info and log level debug", function()
    local pri, message = run({
      method = "GET",
      path = "/request",
      headers = {
        host = "logging1.com"
      }
    })
    assert.equal("14", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity is critical and log level critical", function()
    local pri, message = run({
      method = "GET",
      path = "/request",
      headers = {
        host = "logging2.com"
      }
    })
    assert.equal("10", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity and log level are default values", function()
    local pri, message = run({
      method = "GET",
      path = "/",
      headers = {
        host = "logging3.com"
      }
    })
    assert.equal("14", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity and log level are default values and response status is 200", function()
    local pri, message = run({
      method = "GET",
      path = "/",
      headers = {
        host = "logging3.com"
      }
    })
    assert.equal("14", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity and log level are default values and response status is 401", function()
    local pri, message = run({
      method = "GET",
      path = "/status/401",
      headers = {
        host = "logging3.com"
      }
    }, 401)
    assert.equal("14", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
  it("logs to UDP when severity and log level are default values and response status is 500", function()
    local pri, message = run({
      method = "GET",
      path = "/status/500",
      headers = {
        host = "logging3.com"
      }
    }, 500)
    assert.equal("14", pri)
    assert.equal("127.0.0.1", message.client_ip)
  end)
end)
