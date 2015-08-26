local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"
local cjson = require "cjson"

local STUB_GET_URL = spec_helper.STUB_GET_URL

describe("ACL Plugin", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "ACL 1", public_dns = "acl1.com", target_url = "http://mockbin.com"},
        {name = "ACL 2", public_dns = "acl2.com", target_url = "http://mockbin.com"},
        {name = "ACL 3", public_dns = "acl3.com", target_url = "http://mockbin.com"},
        {name = "ACL 4", public_dns = "acl4.com", target_url = "http://mockbin.com"},
        {name = "ACL 5", public_dns = "acl5.com", target_url = "http://mockbin.com"},
        {name = "ACL 6", public_dns = "acl6.com", target_url = "http://mockbin.com"},
        {name = "ACL 7", public_dns = "acl7.com", target_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "consumer1"},
        {username = "consumer2"},
        {username = "consumer3"},
        {username = "consumer4"}
      },
      plugin_configuration = {
        {name = "acl", value = { whitelist = {"admin"}}, __api = 1},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 2},
        {name = "acl", value = { whitelist = {"admin"}}, __api = 2},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 3},
        {name = "acl", value = { blacklist = {"admin"}}, __api = 3},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 4},
        {name = "acl", value = { whitelist = {"admin", "pro"}}, __api = 4},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 5},
        {name = "acl", value = { blacklist = {"admin", "pro"}}, __api = 5},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 6},
        {name = "acl", value = { blacklist = {"admin", "pro", "hello"}}, __api = 6},
        {name = "keyauth", value = {key_names = {"apikey"}}, __api = 7},
        {name = "acl", value = { whitelist = {"admin", "pro", "hello"}}, __api = 7}
      },
      keyauth_credential = {
        {key = "apikey123", __consumer = 1},
        {key = "apikey124", __consumer = 2},
        {key = "apikey125", __consumer = 3},
        {key = "apikey126", __consumer = 4}
      },
      acl = {
        {group="admin", __consumer = 2},
        {group="pro", __consumer = 3},
        {group="hello", __consumer = 3},
        {group="free", __consumer = 4},
        {group="hello", __consumer = 4},
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("Simple lists", function()
    it("should fail when an authentication plugin is missing", function()
      local response, status = http_client.get(STUB_GET_URL, {}, {host = "acl1.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("Cannot identify the consumer, add an authentication plugin to use the ACL plugin", body.message)
    end)

    it("should fail when not in whitelist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "acl2.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)

    it("should work when in whitelist", function()
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey124"}, {host = "acl2.com"})
      assert.equal(200, status)
    end)

    it("should work when not in blacklist", function()
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host = "acl3.com"})
      assert.equal(200, status)
    end)

    it("should fail when in blacklist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey124"}, {host = "acl3.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)
  end)

  describe("Multi lists", function()

    it("should work when in whitelist", function()
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey125"}, {host = "acl4.com"})
      assert.equal(200, status)
    end)

    it("should fail when not in whitelist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey126"}, {host = "acl4.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)

    it("should fail when in blacklist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey125"}, {host = "acl5.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)

    it("should work when not in blacklist", function()
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey126"}, {host = "acl5.com"})
      assert.equal(200, status)
    end)

    it("should not work when one of the ACLs in the blacklist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey126"}, {host = "acl6.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)

    it("should work when one of the ACLs in the whitelist", function()
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey126"}, {host = "acl7.com"})
      assert.equal(200, status)
    end)

    it("should not work when at least one of the ACLs in the blacklist", function()
      local response, status = http_client.get(STUB_GET_URL, {apikey = "apikey125"}, {host = "acl6.com"})
      local body = cjson.decode(response)
      assert.equal(403, status)
      assert.equal("You cannot consume this service", body.message)
    end)

  end)

end)
