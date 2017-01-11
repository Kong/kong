local helpers = require "spec.helpers"

local BAD_REGEX = [[(https?:\/\/.*]]  -- illegal regex, errors out

describe("Plugin: bot-detection (API)", function()
  local client

  setup(function()
    assert(helpers.dao.apis:insert {
      name = "bot1.com",
      hosts = { "bot1.com" },
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.apis:insert {
      name = "bot2.com",
      hosts = { "bot2.com" },
      upstream_url = "http://mockbin.com"
    })

    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
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
