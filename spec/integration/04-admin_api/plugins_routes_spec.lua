local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("Admin API", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/plugins/enabled", function()
    local BASE_URL = spec_helper.API_URL.."/plugins/enabled"

    it("should return a list of enabled plugins on this node", function()
      local response, status = http_client.get(BASE_URL)
      assert.equal(200, status)
      local body = json.decode(response)
      assert.is_table(body.enabled_plugins)
    end)
  end)

  describe("/plugins", function()
    local BASE_URL = spec_helper.API_URL.."/plugins/"
    local fixtures

    setup(function()
      fixtures = spec_helper.insert_fixtures {
        api = {
          {request_host = "test-get.com", upstream_url = "http://mockbin.com"},
          {request_host = "test-patch.com", upstream_url = "http://mockbin.com"},
          {request_host = "test-delete.com", upstream_url = "http://mockbin.com"}
        },
        plugin = {
          {name = "key-auth", __api = 1},
          {name = "key-auth", __api = 2},
          {name = "key-auth", __api = 3}
        }
      }
    end)

    describe("GET", function()
      it("[SUCCESS] should retrieve all the plugins", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equal(3, body.total)
      end)
    end)

    describe("/plugins/:id", function()
      describe("GET", function()
        it("[SUCCESS] should GET a plugin", function()
          local response, status = http_client.get(BASE_URL..fixtures.plugin[1].id)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.equal("key-auth", body.name)
          assert.equal(fixtures.api[1].id, body.api_id)
        end)
        it("[FAILURE] should return 404 if not found", function()
          local _, status = http_client.get(BASE_URL.."2f49143e-caba-11e5-9d08-03a86066f7a4")
          assert.equal(404, status)
        end)
      end)

      describe("PATCH", function()
        it("[SUCCESS] should PATCH a plugin", function()
          local response, status = http_client.patch(BASE_URL..fixtures.plugin[2].id, {enabled = false})
          assert.equal(200, status)
          local body = json.decode(response)
          assert.False(body.enabled)

          -- Make sure it really updated it
          local response, status = http_client.get(BASE_URL..fixtures.plugin[2].id)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.False(body.enabled)
        end)
        it("[FAILURE] should return 404 if not found", function()
          local _, status = http_client.patch(BASE_URL.."2f49143e-caba-11e5-9d08-03a86066f7a4")
          assert.equal(404, status)
        end)
        it("[SUCCESS] should update when an immutable field does not change", function()
          -- Retrieve plugin
          local response, status = http_client.get(BASE_URL..fixtures.plugin[2].id)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.False(body.enabled)

          -- Update one field
          body.enabled = true
          body.created_at = nil

          -- Do Update
          local response, status = http_client.patch(BASE_URL..fixtures.plugin[2].id, body)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.True(body.enabled)

          -- Make sure it really updated it
          local response, status = http_client.get(BASE_URL..fixtures.plugin[2].id)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.True(body.enabled)
        end)
      end)

      describe("DELETE", function()
        it("[SUCCESS] should DELETE a plugin", function()
          local _, status = http_client.delete(BASE_URL..fixtures.plugin[3].id)
          assert.equal(204, status)
        end)
        it("[FAILURE] should return 404 if not found", function()
          local _, status = http_client.delete(BASE_URL.."2f49143e-caba-11e5-9d08-03a86066f7a4")
          assert.equal(404, status)
        end)
      end)
    end)
  end)

  describe("/plugins/schema/:name", function()
    local BASE_URL = spec_helper.API_URL.."/plugins/schema/key-auth"

    it("[SUCCESS] should return the schema of a plugin", function()
      local response, status = http_client.get(BASE_URL)
      assert.equal(200, status)
      local body = json.decode(response)
      assert.is_table(body.fields)
    end)
    it("[FAILURE] should return a descriptive error if schema is not found", function()
      local response, status = http_client.get(spec_helper.API_URL.."/plugins/schema/foo")
      assert.equal(404, status)
      local body = json.decode(response)
      assert.equal("No plugin named 'foo'", body.message)
    end)
  end)
end)
