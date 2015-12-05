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

  describe("/apis/", function()
    local BASE_URL = spec_helper.API_URL.."/apis/"

    describe("POST", function()
      it("[SUCCESS] should create an API", function()
        send_content_types(BASE_URL, "POST", {
          name = "api-POST-tests",
          request_host = "api.mockbin.com",
          upstream_url = "http://mockbin.com"
        }, 201, nil, {drop_db = true})
      end)
      it("[FAILURE] should notify of malformed body", function()
        local response, status = http_client.post(BASE_URL, '{"hello":"world"', {["content-type"] = "application/json"})
        assert.are.equal(400, status)
        assert.are.equal('{"message":"Cannot parse JSON body"}\n', response)
      end)
      it("[FAILURE] should return proper errors", function()
        send_content_types(BASE_URL, "POST", {},
        400,
        '{"upstream_url":"upstream_url is required","request_path":"At least a \'request_host\' or a \'request_path\' must be specified","request_host":"At least a \'request_host\' or a \'request_path\' must be specified"}')

        send_content_types(BASE_URL, "POST", {request_host = "api.mockbin.com"},
        400, '{"upstream_url":"upstream_url is required"}')

        send_content_types(BASE_URL, "POST", {
          request_host = "api.mockbin.com",
          upstream_url = "http://mockbin.com"
        }, 409, '{"request_host":"request_host already exists with value \'api.mockbin.com\'"}')
      end)
    end)

    describe("PUT", function()
      setup(function()
        spec_helper.drop_db()
      end)

      it("[SUCCESS] should create and update", function()
        local api = send_content_types(BASE_URL, "PUT", {
          name = "api-PUT-tests",
          request_host = "api.mockbin.com",
          upstream_url = "http://mockbin.com"
        }, 201, nil, {drop_db = true})

        api = send_content_types(BASE_URL, "PUT", {
          id = api.id,
          name = "api-PUT-tests-updated",
          request_host = "updated-api.mockbin.com",
          upstream_url = "http://mockbin.com"
        }, 200)
        assert.equal("api-PUT-tests-updated", api.name)
      end)
      it("[FAILURE] should return proper errors", function()
        send_content_types(BASE_URL, "PUT", {},
        400,
        '{"upstream_url":"upstream_url is required","request_path":"At least a \'request_host\' or a \'request_path\' must be specified","request_host":"At least a \'request_host\' or a \'request_path\' must be specified"}')

        send_content_types(BASE_URL, "PUT", {request_host = "api.mockbin.com"},
        400, '{"upstream_url":"upstream_url is required"}')

        send_content_types(BASE_URL, "PUT", {
          request_host = "updated-api.mockbin.com",
          upstream_url = "http://mockbin.com"
        }, 409, '{"request_host":"request_host already exists with value \'updated-api.mockbin.com\'"}')
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
        assert.equal(10, body.total)
      end)
      it("should retrieve a paginated set", function()
        local response, status = http_client.get(BASE_URL, {size = 3})
        assert.equal(200, status)
        local body_page_1 = json.decode(response)
        assert.truthy(body_page_1.data)
        assert.equal(3, table.getn(body_page_1.data))
        assert.truthy(body_page_1.next)
        assert.equal(10, body_page_1.total)

        response, status = http_client.get(BASE_URL, {size = 3, offset = body_page_1.next})
        assert.equal(200, status)
        local body_page_2 = json.decode(response)
        assert.truthy(body_page_2.data)
        assert.equal(3, table.getn(body_page_2.data))
        assert.truthy(body_page_2.next)
        assert.not_same(body_page_1, body_page_2)
        assert.equal(10, body_page_2.total)

        response, status = http_client.get(BASE_URL, {size = 4, offset = body_page_2.next})
        assert.equal(200, status)
        local body_page_3 = json.decode(response)
        assert.truthy(body_page_3.data)
        assert.equal(4, table.getn(body_page_3.data))
        assert.equal(10, body_page_3.total)
        assert.falsy(body_page_3.next)
        assert.not_same(body_page_2, body_page_3)
      end)
    end)
  end)

  describe("/apis/:api", function()
    local BASE_URL = spec_helper.API_URL.."/apis/"
    local api

    setup(function()
      spec_helper.drop_db()
      local fixtures = spec_helper.insert_fixtures {
        api = {
          {request_host = "mockbin.com", upstream_url = "http://mockbin.com"}
        }
      }
      api = fixtures.api[1]
    end)

    describe("GET", function()
      it("should retrieve by id", function()
        local response, status = http_client.get(BASE_URL..api.id)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.same(api, body)
      end)
      it("should retrieve by name", function()
        local response, status = http_client.get(BASE_URL..api.name)
        assert.equal(200, status)
        local body = json.decode(response)
        assert.same(api, body)
      end)
    end)

    describe("PATCH", function()
      it("[SUCCESS] should update an API", function()
        local response, status = http_client.patch(BASE_URL..api.id, {name = "patch-updated"})
        assert.equal(200, status)
        local body = json.decode(response)
        assert.same("patch-updated", body.name)

        api = body

        response, status = http_client.patch(BASE_URL..api.name, {name = "patch-updated-json"}, {["content-type"] = "application/json"})
        assert.equal(200, status)
        body = json.decode(response)
        assert.same("patch-updated-json", body.name)

        api = body
      end)
      it("[FAILURE] should return proper errors", function()
        local _, status = http_client.patch(BASE_URL.."hello", {name = "patch-updated"})
        assert.equal(404, status)

        local response, status = http_client.patch(BASE_URL..api.id, {upstream_url = ""})
        assert.equal(400, status)
        assert.equal('{"upstream_url":"upstream_url is not a url"}\n', response)
      end)
    end)

    describe("DELETE", function()
      it("[FAILURE] should return proper errors", function()
        local _, status = http_client.delete(BASE_URL.."hello")
        assert.equal(404, status)
      end)
      it("[SUCCESS] should delete an API", function()
        local response, status = http_client.delete(BASE_URL..api.id)
        assert.equal(204, status)
        assert.falsy(response)
      end)
    end)

    describe("/apis/:api/plugins/", function()
      local dao_plugins = spec_helper.get_env().dao_factory.plugins

      setup(function()
        spec_helper.drop_db()
        local fixtures = spec_helper.insert_fixtures {
          api = {
            {request_host = "mockbin.com", upstream_url = "http://mockbin.com"}
          }
        }
        api = fixtures.api[1]
        BASE_URL = BASE_URL..api.id.."/plugins/"
      end)

      describe("POST", function()
        it("[FAILURE] should return proper errors", function()
          send_content_types(BASE_URL, "POST", {},
          400, '{"name":"name is required"}')
        end)
        it("[SUCCESS] should create a plugin configuration", function()
          local response, status = http_client.post(BASE_URL, {
            name = "key-auth",
            ["config.key_names"] = {"apikey"}
          })
          assert.equal(201, status)
          local body = json.decode(response)

          local _, err = dao_plugins:delete({id = body.id, name = body.name})
          assert.falsy(err)

          response, status = http_client.post(BASE_URL, {
            name = "key-auth",
            config = {key_names = {"apikey"}}
          }, {["content-type"] = "application/json"})
          assert.equal(201, status)
          body = json.decode(response)

          _, err = dao_plugins:delete({id = body.id, name = body.name})
          assert.falsy(err)
        end)
      end)

      describe("PUT", function()
        local plugin_id

        it("[FAILURE] should return proper errors", function()
          send_content_types(BASE_URL, "PUT", {},
          400, '{"name":"name is required"}')
        end)
        it("[SUCCESS] should create and update", function()
          local response, status = http_client.put(BASE_URL, {
            name = "key-auth",
            ["config.key_names"] = {"apikey"}
          })
          assert.equal(201, status)
          local body = json.decode(response)

          local _, err = dao_plugins:delete({id = body.id, name = body.name})
          assert.falsy(err)

          response, status = http_client.put(BASE_URL, {
            name = "key-auth",
            config = {key_names = {"apikey"}}
          }, {["content-type"] = "application/json"})
          assert.equal(201, status)
          body = json.decode(response)

          plugin_id = body.id

          response, status = http_client.put(BASE_URL, {
            id = plugin_id,
            name = "key-auth",
            config = {key_names = {"updated_apikey"}}
          }, {["content-type"] = "application/json"})
          assert.equal(200, status)
          body = json.decode(response)
          assert.equal("updated_apikey", body.config.key_names[1])
        end)
        it("should override a plugin's `config` if partial", function()
          local response, status = http_client.put(BASE_URL, {
            id = plugin_id,
            name = "key-auth",
            ["config.key_names"] = {"api_key"},
            ["config.hide_credentials"] = true
          })
          assert.equal(200, status)
          assert.truthy(response)

          response, status = http_client.put(BASE_URL, {
            id = plugin_id,
            name = "key-auth",
            ["config.key_names"] = {"api_key_updated"}
          })
          assert.equal(200, status)
          local body = json.decode(response)
          assert.same({"api_key_updated"}, body.config.key_names)
          assert.falsy(body.hide_credentials)
        end)

      end)

      describe("GET", function()
        it("should retrieve all", function()
          local response, status = http_client.get(BASE_URL)
          assert.equal(200, status)
          local body = json.decode(response)
          assert.truthy(body.data)
          assert.equal(1, table.getn(body.data))
        end)
      end)

      describe("/apis/:api/plugins/:plugin", function()
        local BASE_URL = spec_helper.API_URL.."/apis/"
        local api, plugin

        setup(function()
          spec_helper.drop_db()
          local fixtures = spec_helper.insert_fixtures {
            api = {
              {request_host="mockbin.com", upstream_url="http://mockbin.com"}
            },
            plugin = {
              {name = "key-auth", config = {key_names = {"apikey"}}, __api = 1}
            }
          }
          api = fixtures.api[1]
          plugin = fixtures.plugin[1]
          BASE_URL = BASE_URL..api.id.."/plugins/"
        end)

        describe("GET", function()
          it("should retrieve by id", function()
            local response, status = http_client.get(BASE_URL..plugin.id)
            assert.equal(200, status)
            local body = json.decode(response)
            assert.same(plugin, body)
          end)
        end)

        describe("PATCH", function()
          it("[SUCCESS] should update a plugin", function()
            local response, status = http_client.patch(BASE_URL..plugin.id, {["config.key_names"] = {"key_updated"}})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.same("key_updated", body.config.key_names[1])

            response, status = http_client.patch(BASE_URL..plugin.id, {["config.key_names"] = {"key_updated-json"}}, {["content-type"] = "application/json"})
            assert.equal(200, status)
            body = json.decode(response)
            assert.same("key_updated-json", body.config.key_names[1])
          end)
          it("[FAILURE] should return proper errors", function()
            local _, status = http_client.patch(BASE_URL.."b6cca0aa-4537-11e5-af97-23a06d98af51", {})
            assert.equal(404, status)
          end)
          it("should not override a plugin's `config` if partial", function()
            -- This is delicate since a plugin's `config` is a text field in a DB like Cassandra
            local _, status = http_client.patch(BASE_URL..plugin.id, {
              ["config.key_names"] = {"key_set_null_test"},
              ["config.hide_credentials"] = true
            })
            assert.equal(200, status)

            local response, status = http_client.patch(BASE_URL..plugin.id, {
              ["config.key_names"] = {"key_set_null_test_updated"}
            })
            assert.equal(200, status)
            local body = json.decode(response)
            assert.same({"key_set_null_test_updated"}, body.config.key_names)
            assert.equal(true, body.config.hide_credentials)
          end)
          it("should be possible to disable it", function()
            local response, status = http_client.patch(BASE_URL..plugin.id, {
              enabled = false
            })
            assert.equal(200, status)
            local body = json.decode(response)
            assert.False(body.enabled)
          end)
          it("should be possible to enabled it", function()
            local response, status = http_client.patch(BASE_URL..plugin.id, {
              enabled = true
            })
            assert.equal(200, status)
            local body = json.decode(response)
            assert.True(body.enabled)
          end)
        end)

        describe("DELETE", function()
          it("[FAILURE] should return proper errors", function()
            local _, status = http_client.delete(BASE_URL.."b6cca0aa-4537-11e5-af97-23a06d98af51")
            assert.equal(404, status)
          end)
          it("[SUCCESS] should delete a plugin configuration", function()
            local response, status = http_client.delete(BASE_URL..plugin.id)
            assert.equal(204, status)
            assert.falsy(response)
          end)
        end)
      end)
    end)
  end)
end)
