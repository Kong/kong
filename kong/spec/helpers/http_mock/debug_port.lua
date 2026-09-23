local helpers = require "spec.helpers"
local http = require "resty.http"
local cjson = require "cjson"
local match = string.match
local ipairs = ipairs
local insert = table.insert
local assert = assert

local http_mock = {}

-- POST as it's not idempotent
local retrieve_mocking_logs_param = {
  method = "POST",
  path = "/logs",
  headers = {
    ["Host"] = "mock_debug"
  }
}

local purge_mocking_logs_param = {
  method = "DELETE",
  path = "/logs",
  headers = {
    ["Host"] = "mock_debug"
  }
}

local get_status_param = {
  method = "GET",
  path = "/status",
  headers = {
    ["Host"] = "mock_debug"
  }
}

-- internal API
function http_mock:_setup_debug(debug_param)
  local debug_port = helpers.get_available_port()
  local debug_client = assert(http.new())
  local debug_connect = {
    scheme = "http",
    host = "localhost",
    port = debug_port,
  }

  self.debug = {
    port = debug_port,
    client = debug_client,
    connect = debug_connect,
    param = debug_param,
  }
end

function http_mock:debug_connect()
  local debug = self.debug
  local client = debug.client
  assert(client:connect(debug.connect))
  return client
end

function http_mock:retrieve_mocking_logs_json()
  local debug = self:debug_connect()
  local res = assert(debug:request(retrieve_mocking_logs_param))
  assert(res.status == 200)
  local body = assert(res:read_body())
  debug:close()
  return body
end

function http_mock:purge_mocking_logs()
  local debug = self:debug_connect()
  local res = assert(debug:request(purge_mocking_logs_param))
  assert(res.status == 204)
  debug:close()
  return true
end

function http_mock:retrieve_mocking_logs()
  local new_logs = cjson.decode(self:retrieve_mocking_logs_json())
  for _, log in ipairs(new_logs) do
    insert(self.logs, log)
  end

  return new_logs
end

function http_mock:wait_until_no_request(timeout)
  local debug = self:debug_connect()

  -- wait until we have no requests on going
  helpers.wait_until(function()
    local res = assert(debug:request(get_status_param))
    assert(res.status == 200)
    local body = assert(res:read_body())
    local reading, writing, _ = match(body, "Reading: (%d+) Writing: (%d+) Waiting: (%d+)")
    -- the status is the only request
    return assert(reading) + assert(writing) <= 1
  end, timeout)
end

function http_mock:get_all_logs(timeout)
  self:wait_until_no_request(timeout)
  self:retrieve_mocking_logs()
  return self.logs
end

function http_mock:clean(timeout)
  -- if we wait, the http_client may timeout and cause error
  -- self:wait_until_no_request(timeout)

  -- clean unwanted logs
  self.logs = {}
  self:purge_mocking_logs()
  return true
end

return http_mock
