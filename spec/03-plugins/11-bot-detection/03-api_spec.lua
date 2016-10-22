local helpers = require "spec.helpers"

local BAD_REGEX = [[(https?:\/\/.*]]  -- illegal regex, errors out

describe("Plugin: bot-detection (API)", function()
  local client
  setup(function()
    assert(helpers.start_kong())
    assert(helpers.dao.apis:insert {
      request_host = "bot1.com",
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      request_host = "bot2.com",
      upstream_url = "http://mockbin.com"
    })
  end)
  teardown(function()
    helpers.kill_all()
  end)

  before_each(function()
    client = helpers.admin_client()
  end)
  after_each(function()
    if client then client:close() end
  end)

  it("fails when whitelisting a bad regex", function()
    local res = assert(client:send {
      method = "POST",
      path = "/apis/bot1.com/plugins/",
      body = {
        name = "bot-detection",
        ["config.whitelist"] = { BAD_REGEX }
      },
      headers = {
        ["content-type"] = "application/json"
      }
    })
    assert.response(res).has.status(400)
  end)

  it("fails when blacklisting a bad regex", function()
    local res = assert(client:send {
      method = "POST",
      path = "/apis/bot2.com/plugins/",
      body = {
        name = "bot-detection",
        ["config.whitelist"] = { BAD_REGEX }
      },
      headers = {
        ["content-type"] = "application/json"
      }
    })
    assert.response(res).has.status(400)
  end)
end)
