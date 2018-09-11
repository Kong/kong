local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_stringx = require "pl.stringx"

describe("#flaky Plugin: syslog (log)", function()
  local client, platform
  setup(function()
    helpers.run_migrations()

    local api1 = assert(helpers.dao.apis:insert {
      name         = "api-1",
      hosts        = { "logging.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api2 = assert(helpers.dao.apis:insert {
      name         = "api-2",
      hosts        = { "logging2.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    local api3 = assert(helpers.dao.apis:insert {
      name         = "api-3",
      hosts        = { "logging3.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.db.plugins:insert {
      api = { id = api1.id },
      name   = "syslog",
      config = {
        log_level              = "info",
        successful_severity    = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning",
      },
    })
    assert(helpers.db.plugins:insert {
      api = { id = api2.id },
      name   = "syslog",
      config = {
        log_level              = "err",
        successful_severity    = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning",
      },
    })
    assert(helpers.db.plugins:insert {
      api = { id = api3.id },
      name   = "syslog",
      config = {
        log_level              = "warning",
        successful_severity    = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning",
      },
    })

    local ok, _, stdout = helpers.execute("uname")
    assert(ok, "failed to retrieve platform name")
    platform = pl_stringx.strip(stdout)

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.get_proxy_port(false)))
  end)
  after_each(function()
    if client then client:close() end
  end)

  local function do_test(host, expecting_same)
    local uuid = utils.uuid()

    local response = assert(client:send {
      method = "GET",
      path = "/request",
      headers = {
        host = host,
        sys_log_uuid = uuid,
      }
    })
    assert.res_status(200, response)

    if platform == "Darwin" then
      local _, _, stdout = assert(helpers.execute("syslog -k Sender kong | tail -1"))
      local msg = string.match(stdout, "{.*}")
      local json = cjson.decode(msg)

      if expecting_same then
        assert.equal(uuid, json.request.headers["sys-log-uuid"])
      else
        assert.not_equal(uuid, json.request.headers["sys-log-uuid"])
      end
    elseif expecting_same then
      local _, _, stdout = assert(helpers.execute("find /var/log -type f -mmin -5 2>/dev/null | xargs grep -l " .. uuid))
      assert.True(#stdout > 0)
    end
  end

  it("logs to syslog if log_level is lower", function()
    do_test("logging.com", true)
  end)
  it("does not log to syslog if log_level is higher", function()
    do_test("logging2.com", false)
  end)
  it("logs to syslog if log_level is the same", function()
    do_test("logging3.com", true)
  end)
end)
