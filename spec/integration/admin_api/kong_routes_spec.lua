local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"
local env = spec_helper.get_env() -- test environment
local dao_factory = env.dao_factory

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)
  
  describe("Kong routes", function()
    describe("/", function()
      local constants = require "kong.constants"

      it("should return Kong's version and a welcome message", function()
        local response, status = http_client.get(spec_helper.API_URL)
        assert.are.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body.version)
        assert.truthy(body.tagline)
        assert.are.same(constants.VERSION, body.version)
      end)

      it("should have a Server header", function()
        local _, status, headers = http_client.get(spec_helper.API_URL)
        assert.are.same(200, status)
        assert.are.same(string.format("%s/%s", constants.NAME, constants.VERSION), headers.server)
        assert.falsy(headers.via) -- Via is only set for proxied requests
      end)

      it("should return method not allowed", function()
        local res, status = http_client.post(spec_helper.API_URL)
        assert.are.same(405, status)
        assert.are.same("Method not allowed", json.decode(res).message)

        local res, status = http_client.delete(spec_helper.API_URL)
        assert.are.same(405, status)
        assert.are.same("Method not allowed", json.decode(res).message)

        local res, status = http_client.put(spec_helper.API_URL)
        assert.are.same(405, status)
        assert.are.same("Method not allowed", json.decode(res).message)

        local res, status = http_client.patch(spec_helper.API_URL)
        assert.are.same(405, status)
        assert.are.same("Method not allowed", json.decode(res).message)
      end)
    end)
  end)

  describe("/status", function()
    it("should return status information", function()
      local response, status = http_client.get(spec_helper.API_URL.."/status")
      assert.are.equal(200, status)
      local body = json.decode(response)
      assert.truthy(body)
      assert.are.equal(2, utils.table_size(body))

      -- Database stats
      -- Removing migrations DAO
      dao_factory.daos.migrations = nil
      assert.are.equal(utils.table_size(dao_factory.daos), utils.table_size(body.database))
      for k, _ in pairs(dao_factory.daos) do
        assert.truthy(body.database[k])
      end

      -- Server stats
      assert.are.equal(7, utils.table_size(body.server))
      assert.truthy(body.server.connections_accepted)
      assert.truthy(body.server.connections_active)
      assert.truthy(body.server.connections_handled)
      assert.truthy(body.server.connections_reading)
      assert.truthy(body.server.connections_writing)
      assert.truthy(body.server.connections_waiting)
      assert.truthy(body.server.total_requests)
    end)
  end)

  describe("Request size", function()
    it("should properly hanlde big POST bodies < 10MB", function()
      local response, status = http_client.post(spec_helper.API_URL.."/apis", { request_path = "hello.com", upstream_url = "http://mockbin.org" })
      assert.equal(201, status)
      local api_id = json.decode(response).id
      assert.truthy(api_id)


      local big_value = string.rep("204.48.16.0,", 1000)
      big_value = string.sub(big_value, 1, string.len(big_value) - 1)
      assert.truthy(string.len(big_value) > 10000) -- More than 10kb

      local _, status = http_client.post(spec_helper.API_URL.."/apis/"..api_id.."/plugins/", { name = "ip-restriction", ["config.blacklist"] = big_value})
      assert.equal(201, status)
    end)

    it("should fail with requests > 10MB", function()
      local response, status = http_client.post(spec_helper.API_URL.."/apis", { request_path = "hello2.com", upstream_url = "http://mockbin.org" })
      assert.equal(201, status)
      local api_id = json.decode(response).id
      assert.truthy(api_id)

      -- It should fail with more than 10MB
      local big_value = string.rep("204.48.16.0,", 1024000)
      big_value = string.sub(big_value, 1, string.len(big_value) - 1)
      assert.truthy(string.len(big_value) > 10000000) -- More than 10kb

      local _, status = http_client.post(spec_helper.API_URL.."/apis/"..api_id.."/plugins/", { name = "ip-restriction", ["config.blacklist"] = big_value})
      assert.equal(413, status)
    end)
  end)

end)
