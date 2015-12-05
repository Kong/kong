local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

describe("ACLs API", function()
  local BASE_URL, acl, consumer

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/:consumer/acls/", function()

    setup(function()
      local fixtures = spec_helper.insert_fixtures {
        consumer = {{ username = "bob" }}
      }
      consumer = fixtures.consumer[1]
      BASE_URL = spec_helper.API_URL.."/consumers/bob/acls/"
    end)

    describe("POST", function()

      it("[FAILURE] should not create an ACL association without a group name", function()
        local response, status = http_client.post(BASE_URL, { })
        assert.equal(400, status)
        assert.equal("group is required", json.decode(response).group)
      end)

      it("[SUCCESS] should create an ACL association", function()
        local response, status = http_client.post(BASE_URL, { group = "admin" })
        assert.equal(201, status)
        acl = json.decode(response)
        assert.equal(consumer.id, acl.consumer_id)
        assert.equal("admin", acl.group)
      end)

    end)

    describe("PUT", function()

      it("[SUCCESS] should create and update", function()
        local response, status = http_client.put(BASE_URL, { group = "pro" })
        assert.equal(201, status)
        acl = json.decode(response)
        assert.equal(consumer.id, acl.consumer_id)
        assert.equal("pro", acl.group)
      end)

    end)

    describe("GET", function()

      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equal(2, #(body.data))
      end)

    end)

  end)

  describe("/consumers/:consumer/acl/:id", function()

    describe("GET", function()

      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..acl.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.equals(acl.id, body.id)
      end)

    end)

    describe("PATCH", function()

      it("[SUCCESS] should update an ACL association", function()
        local response, status = http_client.patch(BASE_URL..acl.id, { group = "basic" })
        assert.equal(200, status)
        acl = json.decode(response)
        assert.equal("basic", acl.group)
      end)

      it("[FAILURE] should return proper errors", function()
        local response, status = http_client.patch(BASE_URL..acl.id, { group = "" })
        assert.equal(400, status)
        assert.equal('{"group":"group is not a string"}\n', response)
      end)

    end)

    describe("DELETE", function()

      it("[FAILURE] should return proper errors", function()
        local _, status = http_client.delete(BASE_URL.."blah")
        assert.equal(400, status)

        _, status = http_client.delete(BASE_URL.."00000000-0000-0000-0000-000000000000")
        assert.equal(404, status)
      end)

      it("[SUCCESS] should delete an ACL association", function()
        local _, status = http_client.delete(BASE_URL..acl.id)
        assert.equal(204, status)
      end)

    end)

  end)

end)
