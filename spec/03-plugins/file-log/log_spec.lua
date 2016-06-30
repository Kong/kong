local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local pl_path = require "pl.path"
local pl_file = require "pl.file"
local pl_stringx = require "pl.stringx"

local FILE_LOG_PATH = os.tmpname()

describe("Plugin: file-log", function()
  local client
  setup(function()
    helpers.kill_all()

    local api1 = assert(helpers.dao.apis:insert {
      request_host = "file_logging.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      api_id = api1.id,
      name = "file-log",
      config = {
        path = FILE_LOG_PATH
      }
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.proxy_port))
  end)

  after_each(function()
    if client then client:close() end
  end)

  it("logs to file", function()
    local uuid = utils.random_string()

    -- Making the request
    local res = assert(client:send({
      method = "GET",
      path = "/status/200",
      headers = {
        ["file-log-uuid"] = uuid,
        ["Host"] = "file_logging.com"
      }
    }))
    assert.res_status(200, res)

    helpers.wait_until(function()
      return pl_path.exists(FILE_LOG_PATH) and pl_path.getsize(FILE_LOG_PATH) > 0
    end, 10)

    local file_log = pl_file.read(FILE_LOG_PATH)
    local log_message = cjson.decode(pl_stringx.strip(file_log))
    assert.same("127.0.0.1", log_message.client_ip)
    assert.same(uuid, log_message.request.headers["file-log-uuid"])

    os.remove(FILE_LOG_PATH)
  end)
end)
