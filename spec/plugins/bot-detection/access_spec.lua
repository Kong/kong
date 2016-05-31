local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local PROXY_URL = spec_helper.PROXY_URL
local STUB_GET_URL = PROXY_URL.."/request"

local HELLOWORLD = "HelloWorld"
local FACEBOOK = "facebookexternalhit/1.1"

describe("Logging Plugins", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { request_host = "bot.com", upstream_url = "http://mockbin.com" },
        { request_host = "bot2.com", upstream_url = "http://mockbin.com" },
        { request_host = "bot3.com", upstream_url = "http://mockbin.com" }
      },
      plugin = {
        { name = "bot-detection", config = {}, __api = 1 },
        { name = "bot-detection", config = {blacklist = HELLOWORLD}, __api = 2 },
        { name = "bot-detection", config = {whitelist = FACEBOOK}, __api = 3 }
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should not block regular requests", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com" })
    assert.are.equal(200, status)
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/50.0.2661.102 Safari/537.36" })
    assert.are.equal(200, status)
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = HELLOWORLD })
    assert.are.equal(200, status)
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "curl/7.43.0" })
    assert.are.equal(200, status)
  end)

  it("should block bots", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = "Googlebot/2.1 (+http://www.google.com/bot.html)" })
    assert.are.equal(403, status)
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot.com", ["user-agent"] = FACEBOOK })
    assert.are.equal(403, status)
  end)

  it("should block blacklisted user-agents", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot3.com", ["user-agent"] = HELLOWORLD })
    assert.are.equal(200, status)
  end)

  it("should allow whitelisted user-agents", function()
    local _, status = http_client.get(STUB_GET_URL, nil, { host = "bot3.com", ["user-agent"] = FACEBOOK })
    assert.are.equal(200, status)
  end)
  
end)
