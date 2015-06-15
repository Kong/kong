local json = require "cjson"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"
local send_content_types = require "spec.integration.admin_api.helpers"

describe("Admin API", function()

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  describe("/consumers/", function()
    local BASE_URL = spec_helper.API_URL.."/consumers/"

    describe("POST", function()

      it("[SUCCESS] should create a Consumer", function()
        send_content_types(BASE_URL, "POST", {
          username="consumer POST tests"
        }, 201, nil, {drop_db=true})
      end)

      it("[FAILURE] should return proper errors", function()
        send_content_types(BASE_URL, "POST", {},
        400,
        '{"custom_id":"At least a \'custom_id\' or a \'username\' must be specified","username":"At least a \'custom_id\' or a \'username\' must be specified"}')

        send_content_types(BASE_URL, "POST", {
          username="consumer POST tests"
        }, 409, '{"username":"username already exists with value \'consumer POST tests\'"}')
      end)

    end)

    describe("PUT", function()

      it("[SUCCESS] should create and update", function()
        local consumer = send_content_types(BASE_URL, "PUT", {
          username="consumer PUT tests"
        }, 201, nil, {drop_db=true})

        consumer = send_content_types(BASE_URL, "PUT", {
          id=consumer.id,
          username="consumer PUT tests updated",
        }, 200)
        assert.equal("consumer PUT tests updated", consumer.username)
      end)

      it("[FAILURE] should return proper errors", function()
        send_content_types(BASE_URL, "PUT", {},
        400,
        '{"custom_id":"At least a \'custom_id\' or a \'username\' must be specified","username":"At least a \'custom_id\' or a \'username\' must be specified"}')

        send_content_types(BASE_URL, "PUT", {
          username="consumer PUT tests updated",
        }, 409, '{"username":"username already exists with value \'consumer PUT tests updated\'"}')
      end)

    end)

    describe("GET", function()

      setup(function()
        spec_helper.drop_db()
        spec_helper.seed_db(10)
      end)

      it("should retrieve all", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body.data)
        assert.equal(10, table.getn(body.data))
      end)

      it("should retrieve a paginated set", function()
        local response, status = http_client.get(BASE_URL, {size=3})
        assert.equal(200, status)
        local body_page_1 = json.decode(response)
        assert.truthy(body_page_1.data)
        assert.equal(3, table.getn(body_page_1.data))
        assert.truthy(body_page_1.next)

        response, status = http_client.get(BASE_URL, {size=3,offset=body_page_1.next})
        assert.equal(200, status)
        local body_page_2 = json.decode(response)
        assert.truthy(body_page_2.data)
        assert.equal(3, table.getn(body_page_2.data))
        assert.truthy(body_page_2.next)
        assert.not_same(body_page_1, body_page_2)

        response, status = http_client.get(BASE_URL, {size=4,offset=body_page_2.next})
        assert.equal(200, status)
        local body_page_3 = json.decode(response)
        assert.truthy(body_page_3.data)
        assert.equal(4, table.getn(body_page_3.data))
        -- TODO: fixme
        --assert.falsy(body_page_3.next)
        assert.not_same(body_page_2, body_page_3)
      end)

    end)

    describe("/consumers/:consumer", function()
      local consumer

      setup(function()
        spec_helper.drop_db()
        local fixtures = spec_helper.insert_fixtures {
          consumer = {{ username="get_consumer_tests" }}
        }
        consumer = fixtures.consumer[1]
      end)

      describe("GET", function()

        it("should retrieve by id", function()
          local response, status = http_client.get(BASE_URL..consumer.id)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same(consumer, body)
        end)

        it("should retrieve by username", function()
          local response, status = http_client.get(BASE_URL..consumer.username)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same(consumer, body)
        end)

      end)

      describe("PATCH", function()

        it("[SUCCESS] should update a Consumer", function()
          local response, status = http_client.patch(BASE_URL..consumer.id, {username="patch-updated"})
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same("patch-updated", body.username)

          consumer = body

          response, status = http_client.patch(BASE_URL..consumer.username, {username="patch-updated-json"}, {["content-type"]="application/json"})
          assert.equal(200, status)
          body = json.decode(response)
          assert.same("patch-updated-json", body.username)

          consumer = body
        end)

        it("[FAILURE] should return proper errors", function()
          local _, status = http_client.patch(BASE_URL.."hello", {username="patch-updated"})
          assert.equal(404, status)

          local response, status = http_client.patch(BASE_URL..consumer.id, {username=" "})
          assert.equal(400, status)
          assert.equal('{"username":"At least a \'custom_id\' or a \'username\' must be specified"}\n', response)
        end)
      end)

      describe("DELETE", function()

        it("[FAILURE] should return proper errors", function()
          local _, status = http_client.delete(BASE_URL.."hello")
          assert.equal(404, status)
        end)

        it("[SUCCESS] should delete a Consumer", function()
          local response, status = http_client.delete(BASE_URL..consumer.id)
          assert.equal(204, status)
          assert.falsy(response)
        end)

      end)
    end)
  end)
end)
