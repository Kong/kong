local utils = require "kong.tools.utils"
local cjson = require "cjson"
local helpers = require "spec.helpers"
local exec = require("pl.utils").executeex

describe("Syslog #ci", function()

  local client, platform
  
  setup(function()
    helpers.dao:truncate_tables()
    assert(helpers.prepare_prefix())

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
      },
    })

    assert(helpers.dao.plugins:insert {
      api_id = api2.id,
      name = "syslog", 
      config = { 
        log_level = "err", 
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      },
    })
      
    assert(helpers.dao.plugins:insert {
      api_id = api3.id,
      name = "syslog", 
      config = { 
        log_level = "warning", 
        successful_severity = "warning",
        client_errors_severity = "warning",
        server_errors_severity = "warning"
      },
    })
    
    local success, code, _
    success, code, platform, _ = exec("/bin/uname")
    if code ~= 0 then
      success, code, platform, _ = exec("/usr/bin/uname")
    end
    assert(code == 0, "Failed to retrieve platform name")
    assert(helpers.start_kong())
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)
  
  after_each(function()
    if client then client:close() end
  end)

  local function do_test(host, expecting_same)
    local uuid = utils.random_string()

    -- Making the request
    local response = assert( client:send {
        method = "GET",
        path = "/request",
        headers = {
          host = host, 
          sys_log_uuid = uuid,
        },
      })
    
    assert.has.res_status(200, response)
    
    if platform == "Darwin" then
      local success, code, output, errout = exec("syslog -k Sender kong | tail -1")
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
        local success, code, output, errout = exec("find /var/log -type f -mmin -5 2>/dev/null | xargs grep -l "..uuid)
        assert.are.equal(0, code)
        assert.is.True(#output > 0)
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
