local helpers = require "spec.helpers"

local BAD_REGEX = [[(https?:\/\/.*]]  -- illegal regex, errors out

describe("Plugin: bot-detection (API)", function()
  local client

  lazy_setup(function()
    local dao = select(3, helpers.get_db_utils())

    assert(dao.apis:insert {
      name         = "bot1.com",
      hosts        = { "bot1.com" },
      upstream_url = helpers.mock_upstream_url,
    })
    assert(dao.apis:insert {
      name         = "bot2.com",
      hosts        = { "bot2.com" },
      upstream_url = helpers.mock_upstream_url,
    })

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))
  end)

  lazy_teardown(function()
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
