local cjson = require "cjson"
local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local PROXY_URL = spec_helper.PROXY_URL
local STUB_GET_URL = PROXY_URL.."/request"
local API_URL = spec_helper.API_URL

describe("Hooks", function()

  local plugin_id

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "bot.com", upstream_url = "http://mockbin.com" }
      },
      plugin = {
        { name = "bot-detection", config = {}, __api = 1 }
      }
    }

    spec_helper.start_kong()

    local response, status = http_client.get(API_URL.."/apis/bot.com/plugins/")
    assert.equals(200, status)
    plugin_id = cjson.decode(response).data[1].id
    assert.truthy(plugin_id)
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should block a newly entered user-agent", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "helloworld" })
    assert.are.equal(200, status)

    -- Update the plugin
    local _, status = http_client.patch(API_URL.."/apis/bot.com/plugins/"..plugin_id, {["config.blacklist"] = "helloworld"})
    assert.are.equal(200, status)

    repeat
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "helloworld" })
      os.execute("sleep 0.5")
    until(status == 403)

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "helloworld" })
    assert.are.equal(403, status)
  end)

  it("should allow a newly entered user-agent", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "facebookexternalhit/1.1" })
    assert.are.equal(403, status)

    -- Update the plugin
    local _, status = http_client.patch(API_URL.."/apis/bot.com/plugins/"..plugin_id, {["config.whitelist"] = "facebookexternalhit/1.1"})
    assert.are.equal(200, status)

    repeat
      local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "facebookexternalhit/1.1" })
      os.execute("sleep 0.5")
    until(status == 200)

    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "facebookexternalhit/1.1" })
    assert.are.equal(200, status)
  end)
  
end)
