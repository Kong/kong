local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local stringy = require "stringy"
local cjson = require "cjson"
local yaml = require "yaml"
local uuid = require "uuid"
local IO = require "kong.tools.io"

-- This is important to seed the UUID generator
uuid.seed()

describe("Real IP", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "tests realip", public_dns = "realip.com", target_url = "http://mockbin.com" }
      },
      plugin_configuration = {
        { name = "filelog", value = {}, __api = 1 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should parse the correct IP", function()
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

    -- Reading the log file and finding the line with the entry
    local configuration = yaml.load(IO.read_file(spec_helper.TEST_CONF_FILE))
    assert.truthy(configuration)
    local error_log = IO.read_file(configuration.nginx_working_dir.."/logs/error.log")
    local line
    local lines = stringy.split(error_log, "\n")
    for _, v in ipairs(lines) do
      if string.find(v, uuid, nil, true) then
        line = v
        break
      end
    end
    assert.truthy(line)

    -- Retrieve the JSON part of the line
    local json_str = line:match("(%{.*%})")
    assert.truthy(json_str)

    local log_message = cjson.decode(json_str)
    assert.are.same("4.4.4.4", log_message.client_ip)
    assert.are.same(uuid, log_message.request.headers.file_log_uuid)
  end)

end)
