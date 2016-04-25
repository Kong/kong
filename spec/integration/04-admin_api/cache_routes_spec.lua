local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local cache = require "kong.tools.database_cache"

local GET_URL = spec_helper.STUB_GET_URL

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "api-cache", request_host = "cache.com", upstream_url = "http://mockbin.org/"},
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/cache/", function()
    local BASE_URL = spec_helper.API_URL.."/cache/"

    describe("GET", function()

      it("[FAILURE] should return an error when the key is invalid", function()
        local _, status = http_client.get(BASE_URL.."hello")
        assert.equal(404, status)
      end)

      it("[SUCCESS] should get the value of a cache item", function()
        -- Populating cache
        local _, status = http_client.get(GET_URL, {}, {host = "cache.com"})
        assert.equal(200, status)

        -- Retrieving cache
        local response, status = http_client.get(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(200, status)
        assert.truthy(json.decode(response).by_dns)
      end)

    end)

    describe("DELETE", function()

      it("[SUCCESS] should invalidate an entity", function()
        -- Populating cache
        local _, status = http_client.get(GET_URL, {}, {host = "cache.com"})
        assert.equal(200, status)

        -- Retrieving cache
        local response, status = http_client.get(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(200, status)
        assert.truthy(json.decode(response).by_dns)

        -- Delete
        local _, status = http_client.delete(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(204, status)

        -- Make sure it doesn't exist
        local _, status = http_client.get(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(404, status)
      end)

      it("[SUCCESS] should invalidate all entities", function()
        -- Populating cache
        local _, status = http_client.get(GET_URL, {}, {host = "cache.com"})
        assert.equal(200, status)

        -- Retrieving cache
        local response, status = http_client.get(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(200, status)
        assert.truthy(json.decode(response).by_dns)

        -- Delete
        local _, status = http_client.delete(BASE_URL)
        assert.equal(204, status)

        -- Make sure it doesn't exist
        local _, status = http_client.get(BASE_URL..cache.all_apis_by_dict_key())
        assert.equal(404, status)
      end)
    end)

  end)
end)
