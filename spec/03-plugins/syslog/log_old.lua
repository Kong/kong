local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("Syslog #ci", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "logging.com", upstream_url = "http://mockbin.com"},
        {request_host = "logging2.com", upstream_url = "http://mockbin.com"},
        {request_host = "logging3.com", upstream_url = "http://mockbin.com"}
      },
      plugin = {
        {name = "syslog", config = {log_level = "info", successful_severity = "warning",
                                      client_errors_severity = "warning",
                                      server_errors_severity = "warning"}, __api = 1},
        {name = "syslog", config = {log_level = "err", successful_severity = "warning",
                                      client_errors_severity = "warning",
                                      server_errors_severity = "warning"}, __api = 2},
        {name = "syslog", config = {log_level = "warning", successful_severity = "warning",
                                      client_errors_severity = "warning",
                                      server_errors_severity = "warning"}, __api = 3}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  local function do_test(host, expecting_same)
    local uuid = utils.random_string()

    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil,
      {host = host, sys_log_uuid = uuid}
    )
    assert.equal(200, status)
    local platform, code = IO.os_execute("/bin/uname")
    if code ~= 0 then
      platform, code = IO.os_execute("/usr/bin/uname")
    end
    if code == 0 and platform == "Darwin" then
      local output, code = IO.os_execute("syslog -k Sender kong | tail -1")
      assert.equal(0, code)
      local message = {}
      for w in string.gmatch(output,"{.*}") do
        table.insert(message, w)
      end
      local log_message = cjson.decode(message[1])
      if expecting_same then
        assert.equal(uuid, log_message.request.headers.sys_log_uuid)
      else
        assert.not_equal(uuid, log_message.request.headers.sys_log_uuid)
      end
    else
      if expecting_same then
        local output, code = IO.os_execute("find /var/log -type f -mmin -5 2>/dev/null | xargs grep -l "..uuid)
        assert.equal(0, code)
        assert.truthy(#output > 0)
      end
    end
  end

  it("should log to syslog if log_level is lower", function()
    do_test("logging.com", true)
  end)

  it("should not log to syslog if the log_level is higher", function()
    do_test("logging2.com", false)
  end)

  it("should log to syslog if log_level is the same", function()
    do_test("logging3.com", true)
  end)
end)
