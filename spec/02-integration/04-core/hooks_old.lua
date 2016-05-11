local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"
local utils = require "kong.tools.utils"
local IO = require "kong.tools.io"

local STUB_GET_URL = spec_helper.STUB_GET_URL
local API_URL = spec_helper.API_URL

describe("Core Hooks", function()

  setup(function()
    pcall(spec_helper.stop_kong)
    spec_helper.prepare_db()
  end)

  before_each(function()
    spec_helper.drop_db()
    spec_helper.start_kong()
    spec_helper.insert_fixtures {
      api = {
        {request_host = "hooks1.com", upstream_url = "http://mockbin.com"},
        {request_host = "hooks-consumer.com", upstream_url = "http://mockbin.com"},
        {request_host = "hooks-plugins.com", upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "consumer1"}
      },
      plugin = {
        {name = "basic-auth", config = {}, __api = 2},
        {name = "basic-auth", config = {}, __api = 3},
        {name = "rate-limiting", config = {minute=10}, __api = 3},
        {name = "rate-limiting", config = {minute=3}, __api = 3, __consumer = 1}
      },
      basicauth_credential = {
        {username = "user123", password = "pass123", __consumer = 1}
      }
    }
  end)

  after_each(function()
    pcall(spec_helper.stop_kong())
  end)

  describe("Plugin entity invalidation", function()
    it("should invalidate a plugin when deleting", function()
      -- Making a request to populate the cache
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks-consumer.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("basic-auth", api_id, nil))
      assert.equals(200, status)

      -- Delete plugin
      local response, status = http_client.get(API_URL.."/apis/"..api_id.."/plugins/", {name="basic-auth"})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)

      local _, status = http_client.delete(API_URL.."/apis/"..api_id.."/plugins/"..plugin_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("basic-auth", api_id, nil))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again without any authorization
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com"})
      assert.equals(200, status)
    end)

    it("should invalidate a consumer-specific plugin when deleting", function()
      -- Making a request to populate the cache
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "hooks-plugins.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)
      assert.equals(3, tonumber(headers["x-ratelimit-limit-minute"]))

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks-plugins.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local response, status = http_client.get(API_URL.."/consumers/consumer1")
      assert.equals(200, status)
      local consumer_id = json.decode(response).id
      assert.truthy(consumer_id)

      local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("rate-limiting", api_id, consumer_id))
      assert.equals(200, status)

      -- Delete plugin
      local response, status = http_client.get(API_URL.."/apis/"..api_id.."/plugins/", {name="rate-limiting", consumer_id=consumer_id})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)

      local _, status = http_client.delete(API_URL.."/apis/"..api_id.."/plugins/"..plugin_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("rate-limiting", api_id, consumer_id))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "hooks-plugins.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)
      assert.equals(10, tonumber(headers["x-ratelimit-limit-minute"]))
    end)

    it("should invalidate a consumer-specific plugin when updating", function()
      -- Making a request to populate the cache
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "hooks-plugins.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)
      assert.equals(3, tonumber(headers["x-ratelimit-limit-minute"]))

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks-plugins.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local response, status = http_client.get(API_URL.."/consumers/consumer1")
      assert.equals(200, status)
      local consumer_id = json.decode(response).id
      assert.truthy(consumer_id)

      local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("rate-limiting", api_id, consumer_id))
      assert.equals(200, status)

      -- Update plugin
      local response, status = http_client.get(API_URL.."/apis/"..api_id.."/plugins/", {name="rate-limiting", consumer_id=consumer_id})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)

      local _, status = http_client.patch(API_URL.."/apis/"..api_id.."/plugins/"..plugin_id, {enabled=false})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("rate-limiting", api_id, consumer_id))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status, headers = http_client.get(STUB_GET_URL, {}, {host = "hooks-plugins.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)
      assert.equals(10, tonumber(headers["x-ratelimit-limit-minute"]))
    end)

    it("should invalidate a plugin when updating", function()
      -- Making a request to populate the cache
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks-consumer.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("basic-auth", api_id, nil))
      assert.equals(200, status)

      -- Delete plugin
      local response, status = http_client.get(API_URL.."/apis/"..api_id.."/plugins/", {name="basic-auth"})
      assert.equals(200, status)
      local plugin_id = json.decode(response).data[1].id
      assert.truthy(plugin_id)

      local _, status = http_client.patch(API_URL.."/apis/"..api_id.."/plugins/"..plugin_id, {enabled=false})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.plugin_key("basic-auth", api_id, nil))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again without any authorization
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com"})
      assert.equals(200, status)
    end)
  end)

  describe("Consumer entity invalidation", function()
    it("should invalidate a consumer when deleting", function()
      -- Making a request to populate the cache
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/consumers/consumer1")
      assert.equals(200, status)
      local consumer_id = json.decode(response).id
      assert.truthy(consumer_id)

      local response, status = http_client.get(API_URL.."/cache/"..cache.consumer_key(consumer_id))
      assert.equals(200, status)
      assert.equals("consumer1", json.decode(response).username)

      -- Delete consumer
      local _, status = http_client.delete(API_URL.."/consumers/consumer1")
      assert.equals(204, status)

      -- Wait for consumer be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.consumer_key(consumer_id))
        if status ~= 200 then
          exists = false
        end
      end

      -- Wait for Basic Auth credential to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.basicauth_credential_key("user123"))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(403, status)
    end)

    it("should invalidate a consumer when updating", function()
      -- Making a request to populate the cache
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/consumers/consumer1")
      assert.equals(200, status)
      local consumer_id = json.decode(response).id
      assert.truthy(consumer_id)

      local response, status = http_client.get(API_URL.."/cache/"..cache.consumer_key(consumer_id))
      assert.equals(200, status)
      assert.equals("consumer1", json.decode(response).username)

      -- Update consumer
      local _, status = http_client.patch(API_URL.."/consumers/consumer1", {username="updated_consumer1"})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.consumer_key(consumer_id))
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks-consumer.com", authorization = "Basic dXNlcjEyMzpwYXNzMTIz"})
      assert.equals(200, status)

      -- Making sure the cache is updated
      local response, status = http_client.get(API_URL.."/cache/"..cache.consumer_key(consumer_id))
      assert.equals(200, status)
      assert.equals("updated_consumer1", json.decode(response).username)
    end)
  end)

  describe("API entity invalidation", function()
    it("should invalidate ALL_APIS_BY_DICT when adding a new API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(json.decode(response).by_dns["hooks1.com"])
      assert.falsy(json.decode(response).by_dns["dynamic-hooks.com"])

      -- Adding a new API
      local _, status = http_client.post(API_URL.."/apis", {request_host="dynamic-hooks.com", upstream_url="http://mockbin.org"})
      assert.equals(201, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(json.decode(response).by_dns["hooks1.com"])
      assert.truthy(json.decode(response).by_dns["dynamic-hooks.com"])
    end)

    it("should invalidate ALL_APIS_BY_DICT when updating an API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(json.decode(response).by_dns["hooks1.com"])
      assert.equals("http://mockbin.com", json.decode(response).by_dns["hooks1.com"].upstream_url)

      -- Updating API
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks1.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local _, status = http_client.patch(API_URL.."/apis/"..api_id, {upstream_url="http://mockbin.org"})
      assert.equals(200, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(200, status)

      -- Make sure the cache is populated with updated value
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(json.decode(response).by_dns["hooks1.com"])
      assert.equals("http://mockbin.org", json.decode(response).by_dns["hooks1.com"].upstream_url)
    end)

    it("should invalidate ALL_APIS_BY_DICT when deleting an API", function()
      -- Making a request to populate ALL_APIS_BY_DICT
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(200, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(1, utils.table_size(json.decode(response).by_dns))
      assert.truthy(json.decode(response).by_dns["hooks1.com"])

      -- Deleting API
      local response, status = http_client.get(API_URL.."/apis", {request_host="hooks1.com"})
      assert.equals(200, status)
      local api_id = json.decode(response).data[1].id
      assert.truthy(api_id)

      local _, status = http_client.delete(API_URL.."/apis/"..api_id)
      assert.equals(204, status)

      -- Wait for cache to be invalidated
      local exists = true
      while(exists) do
        local _, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
        if status ~= 200 then
          exists = false
        end
      end

      -- Consuming the API again
      local _, status = http_client.get(STUB_GET_URL, {}, {host = "hooks1.com"})
      assert.equals(404, status)

      -- Make sure the cache is populated
      local response, status = http_client.get(API_URL.."/cache/"..cache.all_apis_by_dict_key())
      assert.equals(200, status)
      assert.truthy(0, utils.table_size(json.decode(response).by_dns))
    end)
  end)

  describe("Serf events", function()

    local PID_FILE = "/tmp/serf_test.pid"

    local function start_serf()
      local cmd_args = {
        ["-node"] = "test_node",
        ["-bind"] = "127.0.0.1:9000",
        ["-profile"] = "wan",
        ["-rpc-addr"] = "127.0.0.1:9001"
      }
      setmetatable(cmd_args, require "kong.tools.printable")

      local res, code = IO.os_execute("nohup serf agent "..tostring(cmd_args).." 2>&1 & echo $! > "..PID_FILE)
      if code ~= 0 then
        error("Error starting serf: "..res)
      end
    end

    local function stop_serf()
      local pid = IO.read_file(PID_FILE)
      IO.os_execute("kill "..pid)
    end

    it("should syncronize nodes on members events", function()
      start_serf()

      os.execute("sleep 5") -- Wait for both the first member to join, and for the seconday serf to start

      -- Tell Kong to join the new serf
      local _, code = http_client.post(API_URL.."/cluster/", {address = "127.0.0.1:9000"})
      assert.equals(200, code)

      os.execute("sleep 3")

      local res, code = http_client.get(API_URL.."/cluster/")
      local body = json.decode(res)
      assert.equals(200, code)
      assert.equals(2, #body.data)

      local found
      for _, v in ipairs(body.data) do
        if v.address == "127.0.0.1:9000" then
          found = true
          assert.equal("test_node", v.name)
          assert.equal("alive", v.status)
        else
          assert.truthy(v.name)
          assert.equal("alive", v.status)
        end
      end
      assert.True(found)

      -- Killing serf
      stop_serf()

      -- Triggering the status check
      local _, code = IO.os_execute("serf reachability")
      assert.equals(1, code)

      -- Wait a little bit to propagate the data
      os.execute("sleep 45")

      -- Check again
      local res, code = http_client.get(API_URL.."/cluster/")
      local body = json.decode(res)
      assert.equals(200, code)
      assert.equals(2, #body.data)

      local found
      for _, v in ipairs(body.data) do
        if v.address == "127.0.0.1:9000" then
          found = true
          assert.equal("test_node", v.name)
          assert.equal("failed", v.status)
        else
          assert.truthy(v.name)
          assert.equal("alive", v.status)
        end
      end
      assert.True(found)
    end)
  end)
end)
