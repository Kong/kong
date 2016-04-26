local json = require "cjson"
local stringy = require "stringy"
local http_client = require "kong.tools.http_client"
local spec_helper = require "spec.spec_helpers"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/www-url-formencoded")
  local test_json = fn("application/json")
  it(title.." with application/www-form-urlencoded", test_form_encoded)
  it(title.." with application/json", test_json)
end

describe("Admin API", function()
  local consumer_id, consumer

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    local fixtures = spec_helper.insert_fixtures {
      consumer = {
        {username = "api-test", custom_id = "1234"}
      }
    }
    consumer = fixtures.consumer[1]
    consumer_id = consumer.id
  end)

  after_each(function()
    spec_helper.drop_db()
  end)

  describe("/consumers/", function()
    local BASE_URL = spec_helper.API_URL.."/consumers/"

    describe("POST", function()
      it_content_types("should create a Consumer", function(content_type)
        return function()
          local _, status = http_client.post(BASE_URL, {
            username = "consumer POST tests"
          }, {["content-type"] = content_type})
          assert.equal(201, status)
        end
      end)

      describe("errors", function()
        it_content_types("should return proper validation errors", function(content_type)
          return function()
            local response, status = http_client.post(BASE_URL, {}, {["content-type"] = content_type})
            assert.equal(400, status)
            assert.equal([[{"custom_id":"At least a 'custom_id' or a 'username' must be specified","username":"At least a 'custom_id' or a 'username' must be specified"}]], stringy.strip(response))
          end
        end)
        it_content_types("should return HTTP 409 if already exists", function(content_type)
          return function()
            local response, status = http_client.post(BASE_URL, {
              username = "api-test"
            }, {["content-type"] = content_type})
            assert.equal(409, status)
            assert.equal([[{"username":"already exists with value 'api-test'"}]], stringy.strip(response))
          end
        end)
      end)
    end)

    describe("PUT", function()
      it_content_types("should create if not exists", function(content_type)
        return function()
          local _, status = http_client.put(BASE_URL, {
            username = "consumer PUT tests"
          }, {["content-type"] = content_type})
          assert.equal(201, status)
        end
      end)
      it_content_types("should update if exists", function(content_type)
        return function()
          local response, status = http_client.put(BASE_URL, {
            id = consumer_id,
            username = "updated",
            custom_id = "5678",
            created_at = 1461276890000
          }, {["content-type"] = content_type})
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same({
            id = consumer_id,
            username = "updated",
            custom_id = "5678",
            created_at = 1461276890000
          }, body)
        end
      end)
      it_content_types("should update and remove unspecified fields", function(content_type)
        return function()
          local response, status = http_client.put(BASE_URL, {
            id = consumer_id,
            username = "updated",
            created_at = 1461276890000
          }, {["content-type"] = content_type})
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same({
            id = consumer_id,
            username = "updated",
            created_at = 1461276890000
          }, body)
        end
      end)
      describe("errors", function()
        it_content_types("should return proper validation errors", function(content_type)
          return function()
            local response, status = http_client.post(BASE_URL, {}, {["content-type"] = content_type})
            assert.equal(400, status)
            assert.equal([[{"custom_id":"At least a 'custom_id' or a 'username' must be specified","username":"At least a 'custom_id' or a 'username' must be specified"}]], stringy.strip(response))
          end
        end)
        it_content_types("should return HTTP 409 if already exists", function(content_type)
          -- @TODO this test actually defeats the purpose of PUT. It should probably replace the entity
          return function()
            local response, status = http_client.post(BASE_URL, {
              username = "api-test"
            }, {["content-type"] = content_type})
            assert.equal(409, status)
            assert.equal([[{"username":"already exists with value 'api-test'"}]], stringy.strip(response))
          end
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        spec_helper.drop_db()
        spec_helper.seed_db(10)
      end)
      it("should retrieve the first page", function()
        local response, status = http_client.get(BASE_URL)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.truthy(body.data)
        assert.equal(10, table.getn(body.data))
        assert.equal(10, body.total)
      end)
      it("should retrieve a given page", function()
        local response, status = http_client.get(BASE_URL, {size = 3})
        assert.equal(200, status)
        local body_page_1 = json.decode(response)
        assert.truthy(body_page_1.data)
        assert.equal(3, #body_page_1.data)
        assert.truthy(body_page_1.next)
        assert.equal(10, body_page_1.total)

        response, status = http_client.get(BASE_URL, {size = 3, offset = body_page_1.next})
        assert.equal(200, status)
        local body_page_2 = json.decode(response)
        assert.truthy(body_page_2.data)
        assert.equal(3, #body_page_2.data)
        assert.truthy(body_page_2.next)
        assert.not_same(body_page_1, body_page_2)
        assert.equal(10, body_page_2.total)

        response, status = http_client.get(BASE_URL, {size = 3, offset = body_page_2.next})
        assert.equal(200, status)
        local body_page_3 = json.decode(response)
        assert.truthy(body_page_3.data)
        assert.equal(3, #body_page_3.data)
        assert.equal(10, body_page_3.total)
        assert.truthy(body_page_3.next)
        assert.not_same(body_page_2, body_page_3)

        response, status = http_client.get(BASE_URL, {size = 3, offset = body_page_3.next})
        assert.equal(200, status)
        local body_page_4 = json.decode(response)
        assert.truthy(body_page_4.data)
        assert.equal(1, #body_page_4.data)
        assert.equal(10, body_page_4.total)
        assert.falsy(body_page_4.next)
        assert.not_same(body_page_2, body_page_4)
      end)
      it("should refuse to filter with a random field", function()
        local response, status = http_client.get(BASE_URL, {hello="world"})
        assert.equal(400, status)
        local body = json.decode(response)
        assert.equal("unknown field", body.hello)
      end)
    end)

    describe("/consumers/:consumer", function()
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
        it("should reply with HTTP 404 if not found", function()
          local _, status = http_client.get(BASE_URL.."none")
          assert.equal(404, status)
        end)
      end)

      describe("PATCH", function()
        it_content_types("should update if found", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..consumer.id, {
              username = "patch-updated"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("patch-updated", body.username)
          end
        end)
        it_content_types("should update by username", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..consumer.username, {
              username = "patch-updated"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("patch-updated", body.username)
          end
        end)
        describe("errors", function()
          it_content_types("should return 404 if not found", function(content_type)
            return function()
              local _, status = http_client.patch(BASE_URL.."hello", {
                username="patch-updated"
              }, {["content-type"] = content_type})
              assert.equal(404, status)
            end
          end)
          it_content_types("should return proper validation errors", function(content_type)
            return function()
              local response, status = http_client.patch(BASE_URL..consumer.id, {
                username = "",
                custom_id = ""
              }, {["content-type"] = content_type})
              assert.equal(400, status)
              if content_type == "application/json" then
              assert.equal([[{"custom_id":"At least a 'custom_id' or a 'username' must be specified","username":"At least a 'custom_id' or a 'username' must be specified"}]], stringy.strip(response))
              else
                assert.equal([[{"custom_id":"custom_id is not a string","username":"username is not a string"}]], stringy.strip(response))
              end
            end
          end)
        end)
      end)

      describe("DELETE", function()
        local dao_factory = spec_helper.get_env().dao_factory
        setup(function()
          local _, err = dao_factory.consumers:insert {
            username = "to-delete"
          }
          assert.falsy(err)
        end)
        it("delete a Consumer by id", function()
          local response, status = http_client.delete(BASE_URL..consumer.id)
          assert.equal(204, status)
          assert.falsy(response)
        end)
        it("delete a Consumer by name", function()
          local response, status = http_client.delete(BASE_URL..consumer.username)
          assert.equal(204, status)
          assert.falsy(response)
        end)
        describe("error", function()
          it("should return HTTP 404 if not found", function()
            local _, status = http_client.delete(BASE_URL.."hello")
            assert.equal(404, status)
          end)
        end)
      end)
    end)
  end)
end)