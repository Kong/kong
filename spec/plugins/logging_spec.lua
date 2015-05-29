local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local uuid = require "uuid"
local stringy = require "stringy"

-- This is important to seed the UUID generator
uuid.seed()

local STUB_GET_URL = spec_helper.STUB_GET_URL
local TEST_CONF = "kong_TEST.yml"

local TCP_PORT = 20777
local UDP_PORT = 20778
local HTTP_PORT = 20779

local FILE_LOG_PATH = "/tmp/file_log_spec_output.log"

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests tcp logging", public_dns = "tcp_logging.com", target_url = "http://mockbin.com" },
        { name = "tests udp logging", public_dns = "udp_logging.com", target_url = "http://mockbin.com" },
        { name = "tests http logging", public_dns = "http_logging.com", target_url = "http://mockbin.com" },
        { name = "tests file logging", public_dns = "file_logging.com", target_url = "http://mockbin.com" }
      },
      plugin_configuration = {
        { name = "tcplog", value = { host = "127.0.0.1", port = TCP_PORT }, __api = 1 },
        { name = "udplog", value = { host = "127.0.0.1", port = UDP_PORT }, __api = 2 },
        { name = "httplog", value = { http_endpoint = "http://localhost:"..HTTP_PORT }, __api = 3 },
        { name = "filelog", value = { path = FILE_LOG_PATH }, __api = 4 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Invalid API", function()

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

    it("should log to file", function()
      os.remove(FILE_LOG_PATH)

      local uuid = string.gsub(uuid(), "-", "")

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
end)
