local IO = require "kong.tools.io"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local stringy = require "stringy"
local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"


local STUB_GET_URL = spec_helper.STUB_GET_URL

local TCP_PORT = 20777
local UDP_PORT = 20778
local HTTP_PORT = 20779
local HTTP_DELAY_PORT = 20780

local FILE_LOG_PATH = spec_helper.get_env().configuration.nginx_working_dir.."/file_log_spec_output.log"

local function create_mock_bin()
  local res, status = http_client.post("http://mockbin.org/bin/create", '{ "status": 200, "statusText": "OK", "httpVersion": "HTTP/1.1", "headers": [], "cookies": [], "content": { "mimeType" : "application/json" }, "redirectURL": "", "headersSize": 0, "bodySize": 0 }', { ["content-type"] = "application/json" })
  assert.are.equal(201, status)
  return res:sub(2, res:len() - 1)
end

local mock_bin = create_mock_bin()

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests tcp logging", public_dns = "tcp_logging.com", target_url = "http://mockbin.com" },
        { name = "tests tcp logging2", public_dns = "tcp_logging2.com", target_url = "http://localhost:"..HTTP_DELAY_PORT },
        { name = "tests udp logging", public_dns = "udp_logging.com", target_url = "http://mockbin.com" },
        { name = "tests http logging", public_dns = "http_logging.com", target_url = "http://mockbin.com" },
        { name = "tests https logging", public_dns = "https_logging.com", target_url = "http://mockbin.com" },
        { name = "tests file logging", public_dns = "file_logging.com", target_url = "http://mockbin.com" }
      },
      plugin_configuration = {
        { name = "tcplog", value = { host = "127.0.0.1", port = TCP_PORT }, __api = 1 },
        { name = "tcplog", value = { host = "127.0.0.1", port = TCP_PORT }, __api = 2 },
        { name = "udplog", value = { host = "127.0.0.1", port = UDP_PORT }, __api = 3 },
        { name = "httplog", value = { http_endpoint = "http://localhost:"..HTTP_PORT.."/" }, __api = 4 },
        { name = "httplog", value = { http_endpoint = "https://mockbin.org/bin/"..mock_bin }, __api = 5 },
        { name = "filelog", value = { path = FILE_LOG_PATH }, __api = 6 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should log to TCP", function()
    local thread = spec_helper.start_tcp_server(TCP_PORT) -- Starting the mock TCP server

    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "tcp_logging.com" })
    assert.are.equal(200, status)

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log proper latencies", function()
    local http_thread = spec_helper.start_http_server(HTTP_DELAY_PORT) -- Starting the mock TCP server
    local tcp_thread = spec_helper.start_tcp_server(TCP_PORT) -- Starting the mock TCP server

    -- Making the request
    local _, status = http_client.get(spec_helper.PROXY_URL.."/delay", nil, { host = "tcp_logging2.com" })
    assert.are.equal(200, status)

    -- Getting back the TCP server input
    local ok, res = tcp_thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)

    assert.truthy(log_message.latencies.proxy < 3000)
    assert.truthy(log_message.latencies.kong < 100)
    assert.truthy(log_message.latencies.request >= log_message.latencies.kong + log_message.latencies.proxy)

    http_thread:join()
  end)

  it("should log to UDP", function()
    local thread = spec_helper.start_udp_server(UDP_PORT) -- Starting the mock TCP server

    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "udp_logging.com" })
    assert.are.equal(200, status)

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    -- Making sure it's alright
    local log_message = cjson.decode(res)
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to HTTP", function()
    local thread = spec_helper.start_http_server(HTTP_PORT) -- Starting the mock TCP server

    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "http_logging.com" })
    assert.are.equal(200, status)

    -- Getting back the TCP server input
    local ok, res = thread:join()
    assert.truthy(ok)
    assert.truthy(res)

    -- Making sure it's alright
    assert.are.same("POST / HTTP/1.1", res[1])
    local log_message = cjson.decode(res[7])
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to HTTPs", function()
    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "https_logging.com" })
    assert.are.equal(200, status)

    local total_time = 0
    local res, status, body
    repeat
      assert.truthy(total_time <= 10) -- Fail after 10 seconds
      res, status = http_client.get("http://mockbin.org/bin/"..mock_bin.."/log", nil, { accept = "application/json" })
      assert.are.equal(200, status)
      body = cjson.decode(res)
      local wait = 1
      os.execute("sleep "..tostring(wait))
      total_time = total_time + wait
    until(#body.log.entries > 0)

    assert.are.equal(1, #body.log.entries)
    local log_message = cjson.decode(body.log.entries[1].request.postData.text)

    -- Making sure it's alright
    assert.are.same("127.0.0.1", log_message.client_ip)
  end)

  it("should log to file", function()
    os.remove(FILE_LOG_PATH)

    local uuid = utils.random_string()

    -- Making the request
    local _, status = http_client.get(STUB_GET_URL, nil,
      { host = "file_logging.com", file_log_uuid = uuid }
    )
    assert.are.equal(200, status)

    while not (IO.file_exists(FILE_LOG_PATH) and IO.file_size(FILE_LOG_PATH) > 0) do
      -- Wait for the file to be created, and for the log to be appended
    end

    local file_log = IO.read_file(FILE_LOG_PATH)
    local log_message = cjson.decode(stringy.strip(file_log))
    assert.are.same("127.0.0.1", log_message.client_ip)
    assert.are.same(uuid, log_message.request.headers.file_log_uuid)
  end)

end)
