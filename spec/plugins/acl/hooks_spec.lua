local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("ACL Hooks", function()

  setup(function()
    spec_helper.prepare_db()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    spec_helper.restart_kong()

    spec_helper.drop_db()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "acl1.com", upstream_url = "http://mockbin.com"},
        {request_host = "acl2.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "consumer1"},
        {username = "consumer2"}
      },
      plugin = {
        {name = "key-auth", config = {key_names = {"apikey"}}, __api = 1},
        {name = "acl", config = { whitelist = {"admin"}}, __api = 1},
        {name = "key-auth", config = {key_names = {"apikey"}}, __api = 2},
        {name = "acl", config = { whitelist = {"ya"}}, __api = 2}
      },
      keyauth_credential = {
        {key = "apikey123", __consumer = 1},
        {key = "apikey124", __consumer = 2}
      },
      acl = {
        {group="admin", __consumer = 1},
        {group="pro", __consumer = 1},
        {group="admin", __consumer = 2}
      }
    }

  end)

  local function get_consumer_id(username)
    local response, status = http_client.get(API_URL.."/consumers/consumer1")
    assert.equals(200, status)
    local consumer_id = json.decode(response).id
    assert.truthy(consumer_id)
    return consumer_id
  end

  local function get_acl_id(consumer_id_or_name, group_name)
    local response, status = http_client.get(API_URL.."/consumers/"..consumer_id_or_name.."/acls/", {group=group_name})
    assert.equals(200, status)
    local body = json.decode(response)
    if #body.data == 1 then
      return body.data[1].id
    end
  end

  describe("ACL entity invalidation", function()
    it("should invalidate when ACL entity is deleted", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.acls_key(get_consumer_id("consumer1"))
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)
      
      -- Delete ACL group (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/consumer1/acls/"..get_acl_id("consumer1", "admin"))
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(403, status)
    end)
    it("should invalidate when ACL entity is updated", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(200, status)

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl2.com"})
      assert.equals(403, status)

      -- Check that cache is populated
      local cache_key = cache.acls_key(get_consumer_id("consumer1"))
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)
      
      -- Update ACL group (which triggers invalidation)
      local _, status = http_client.patch(API_URL.."/consumers/consumer1/acls/"..get_acl_id("consumer1", "admin"), {group="ya"})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(403, status)

      -- It should work now
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl2.com"})
      assert.equals(200, status)
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate when Consumer entity is deleted", function()
      -- It should work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(200, status)

      -- Check that cache is populated
      local cache_key = cache.acls_key(get_consumer_id("consumer1"))
      local _, status = http_client.get(API_URL.."/cache/"..cache_key)
      assert.equals(200, status)
      
      -- Delete Consumer (which triggers invalidation)
      local _, status = http_client.delete(API_URL.."/consumers/consumer1")
      assert.equals(204, status)

      -- Wait for consumer to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache_key)
        if status ~= 200 then
          exists = false
        end
      end

      -- Wait for key to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.keyauth_credential_key("apikey123"))
        if status ~= 200 then
          exists = false
        end
      end

      -- It should not work
      local _, status = http_client.get(STUB_GET_URL, {apikey = "apikey123"}, {host="acl1.com"})
      assert.equals(403, status)
    end)
  end)
      
end)
