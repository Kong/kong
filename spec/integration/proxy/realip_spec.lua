local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local stringy = require "stringy"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local IO = require "kong.tools.io"

local FILE_LOG_PATH = os.tmpname()

describe("Real IP", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests-realip", request_host = "realip.com", upstream_url = "http://mockbin.com" }
      },
      plugin = {
        { name = "file-log", config = { path = FILE_LOG_PATH }, __api = 1 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should parse the correct IP", function()
    local uuid = utils.random_string()

    -- Making the request
    http_client.get(spec_helper.STUB_GET_URL, nil,
      {
        host = "realip.com",
        ["X-Forwarded-For"] = "4.4.4.4, 1.1.1.1, 5.5.5.5",
        file_log_uuid = uuid
      }
    )

    local timeout = 10
    while not (IO.file_exists(FILE_LOG_PATH) and IO.file_size(FILE_LOG_PATH) > 0) do
      -- Wait for the file to be created, and for the log to be appended
      os.execute("sleep 1")
      timeout = timeout -1
      if timeout == 0 then error("Retrieving the ip address timed out") end
    end

    local file_log = IO.read_file(FILE_LOG_PATH)
    local log_message = cjson.decode(stringy.strip(file_log))
    assert.are.same("4.4.4.4", log_message.client_ip)
    assert.are.same(uuid, log_message.request.headers.file_log_uuid)

    os.remove(FILE_LOG_PATH)
  end)

end)
