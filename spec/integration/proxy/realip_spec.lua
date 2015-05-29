local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local stringy = require "stringy"
local cjson = require "cjson"
local yaml = require "yaml"
local uuid = require "uuid"
local IO = require "kong.tools.io"

-- This is important to seed the UUID generator
uuid.seed()

local FILE_LOG_PATH = spec_helper.get_env().configuration.nginx_working_dir.."/file_log_spec_output.log"

describe("Real IP", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests realip", public_dns = "realip.com", target_url = "http://mockbin.com" }
      },
      plugin_configuration = {
        { name = "filelog", value = { path = FILE_LOG_PATH }, __api = 1 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should parse the correct IP", function()
    os.remove(FILE_LOG_PATH)

    local uuid = string.gsub(uuid(), "-", "")

    -- Making the request
    local _, status = http_client.get(spec_helper.STUB_GET_URL, nil,
      {
        host = "realip.com",
        ["X-Forwarded-For"] = "4.4.4.4, 1.1.1.1, 5.5.5.5",
        file_log_uuid = uuid
      }
    )
    assert.are.equal(200, status)

    while not (IO.file_exists(FILE_LOG_PATH) and IO.file_size(FILE_LOG_PATH) > 0) do
      -- Wait for the file to be created, and for the log to be appended
    end

    local file_log = IO.read_file(FILE_LOG_PATH)
    local log_message = cjson.decode(stringy.strip(file_log))
    assert.are.same("4.4.4.4", log_message.client_ip)
    assert.are.same(uuid, log_message.request.headers.file_log_uuid)
  end)

end)
