local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local Threads = require "llthreads2.ex"
local cjson = require "cjson"
local yaml = require "yaml"
local IO = require "kong.tools.io"
local uuid = require "uuid"
local stringy = require "stringy"
local rex = require "rex_pcre"

-- This is important to seed the UUID generator
uuid.seed()

local STUB_GET_URL = spec_helper.STUB_GET_URL
local TEST_CONF = "kong_TEST.yml"

local function start_tcp_server()
  local thread = Threads.new({
    function()
      local socket = require "socket"
      local server = assert(socket.bind("*", 7777))
      local client = server:accept()
      local line, err = client:receive()
      if not err then client:send(line .. "\n") end
      client:close()
      return line
    end;
  })

  thread:start()
  return thread;
end

local function start_udp_server()
  local thread = Threads.new({
    function()
      local socket = require("socket")
      udp = socket.udp()
      udp:setsockname("*", 8888)
      data, ip, port = udp:receivefrom()
      return data
    end;
  })

  thread:start()
  return thread;
end

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
    spec_helper.reset_db()
  end)

  describe("Invalid API", function()

    it("should log to TCP", function()
      local thread = start_tcp_server() -- Starting the mock TCP server

      -- Making the request
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test1.com"})
      assert.are.equal(200, status)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.truthy(ok)
      assert.truthy(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.are.same("127.0.0.1", log_message.ip)
    end)

    it("should log to UDP", function()
      local thread = start_udp_server() -- Starting the mock TCP server

      -- Making the request
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test1.com"})
      assert.are.equal(200, status)

      -- Getting back the TCP server input
      local ok, res = thread:join()
      assert.truthy(ok)
      assert.truthy(res)

      -- Making sure it's alright
      local log_message = cjson.decode(res)
      assert.are.same("127.0.0.1", log_message.ip)
    end)

    it("should log to file", function()
      local uuid,_ = string.gsub(uuid(), "-", "")

      -- Making the request
      local response, status, headers = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "test1.com", file_log_uuid = uuid})
      assert.are.equal(200, status)

      -- Reading the log file and finding the entry
      local configuration = yaml.load(IO.read_file(TEST_CONF))
      assert.truthy(configuration)
      local error_log = IO.read_file(configuration.nginx_working_dir.."/logs/error.log")
      local line
      local lines = stringy.split(error_log, "\n")
      for _, v in ipairs(lines) do
        if string.find(v, uuid) then
          line = v
          break
        end
      end
      assert.truthy(line)

      -- Matching the Json
      local iterator, iter_err = rex.gmatch(line, "\\s+({.+})\\s+")
      if not iterator then
        error(iter_err)
      end
      local m, err = iterator()
      if err then
        error(err)
      end
      assert.truthy(m)

      local log_message = cjson.decode(m)
      assert.are.same("127.0.0.1", log_message.ip)
      assert.are.same(uuid, log_message.request.headers.file_log_uuid)
    end)

  end)

end)
