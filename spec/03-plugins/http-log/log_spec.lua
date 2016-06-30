local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_stringx = require "pl.stringx"

describe("Plugin: tcp-log", function()
  local client, platform
  setup(function()
    helpers.dao:truncate_tables()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "logging.com",
      upstream_url = "http://mockbin.com"
    })
    local api2 = assert(helpers.dao.apis:insert {
      request_host = "logging2.com",
      upstream_url = "http://mockbin.com"
    })
    local api3 = assert(helpers.dao.apis:insert {
      request_host = "logging3.com",
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "syslog",
      config = {
        log_level = "info",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "syslog",
      config = {
        log_level = "err",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })

    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "syslog",
      config = {
        log_level = "warning",
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)

  after_each(function()
    if client then client:close() end
  end)

  

end)
