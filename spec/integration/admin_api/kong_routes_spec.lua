local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local utils = require "kong.tools.utils"

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

      assert.are.equal(7, utils.table_size(body))
      assert.truthy(body.connections_accepted)
      assert.truthy(body.connections_active)
      assert.truthy(body.connections_handled)
      assert.truthy(body.connections_reading)
      assert.truthy(body.connections_writing)
      assert.truthy(body.connections_waiting)
      assert.truthy(body.total_requests)
    end)
  end)
end)
