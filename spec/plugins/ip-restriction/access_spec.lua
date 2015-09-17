local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("IP Restriction", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        { name = "iprestriction1", inbound_dns = "test1.com", upstream_url = "http://mockbin.com" },
        { name = "iprestriction2", inbound_dns = "test2.com", upstream_url = "http://mockbin.com" },
        { name = "iprestriction3", inbound_dns = "test3.com", upstream_url = "http://mockbin.com" },
        { name = "iprestriction4", inbound_dns = "test4.com", upstream_url = "http://mockbin.com" },
        { name = "iprestriction7", inbound_dns = "test5.com", upstream_url = "http://mockbin.com" },
        { name = "iprestriction8", inbound_dns = "test6.com", upstream_url = "http://mockbin.com" }
      },
      plugin = {
        { name = "ip-restriction", config = { blacklist = { "127.0.0.1" }}, __api = 1 },
        { name = "ip-restriction", config = { blacklist = { "127.0.0.2" }}, __api = 2 },
        { name = "ip-restriction", config = { whitelist = { "127.0.0.2" }}, __api = 3 },
        { name = "ip-restriction", config = { whitelist = { "127.0.0.1" }}, __api = 4 },
        { name = "ip-restriction", config = { blacklist = { "127.0.0.0/24" }}, __api = 5 },
        { name = "ip-restriction", config = { whitelist = { "127.0.0.1", "127.0.0.2" }}, __api = 6 },
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should block request when IP is in blacklist", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test1.com"})
    local body = cjson.decode(response)
    assert.are.equal(403, status)
    assert.are.equal("Your IP address is not allowed", body.message)
  end)

  it("should allow request when IP is not in blacklist", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test2.com"})
    local body = cjson.decode(response)
    assert.are.equal(200, status)
    assert.are.equal("127.0.0.1", body.clientIPAddress)
  end)

  it("should block request when IP is not in whitelist", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test3.com"})
    local body = cjson.decode(response)
    assert.are.equal(403, status)
    assert.are.equal("Your IP address is not allowed", body.message)
  end)

  it("should allow request when IP is in whitelist", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test4.com"})
    local body = cjson.decode(response)
    assert.are.equal(200, status)
    assert.are.equal("127.0.0.1", body.clientIPAddress)
  end)

  it("should block request when IP is blacklisted with CIDR", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test5.com"})
    local body = cjson.decode(response)
    assert.are.equal(403, status)
    assert.are.equal("Your IP address is not allowed", body.message)
  end)

  it("should allow request when IP is in whitelist with another IP", function()
    local response, status = http_client.get(STUB_GET_URL, {}, {host = "test6.com"})
    local body = cjson.decode(response)
    assert.are.equal(200, status)
    assert.are.equal("127.0.0.1", body.clientIPAddress)
  end)

end)
