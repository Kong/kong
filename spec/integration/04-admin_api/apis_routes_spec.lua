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
  local api
  local dao_factory = spec_helper.get_env().dao_factory

  setup(function()
    spec_helper.prepare_db()
    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  before_each(function()
    local fixtures = spec_helper.insert_fixtures {
      api = {
        {name = "api-test", request_host = "api-test.com", upstream_url = "http://mockbin.com"}
      }
    }
    api = fixtures.api[1]
  end)

  after_each(function()
    spec_helper.drop_db()
  end)

  describe("/apis/", function()
    local BASE_URL = spec_helper.API_URL.."/apis/"

    describe("POST", function()
      it_content_types("should create an API", function(content_type)
        return function()
          local _, status = http_client.post(BASE_URL, {
            name = "new-api",
            request_host = "new-api.com",
            upstream_url = "http://mockbin.com"
          }, {["content-type"] = content_type})
          assert.equal(201, status)
        end
      end)
      describe("errors", function()
        it("should notify of malformed JSON body", function()
          local response, status = http_client.post(BASE_URL, '{"hello":"world"', {["content-type"] = "application/json"})
          assert.equal(400, status)
          assert.equal('{"message":"Cannot parse JSON body"}\n', response)
        end)
        it_content_types("return proper validation errors", function(content_type)
          return function()
            local response, status = http_client.post(BASE_URL, {}, {["content-type"] = content_type})
            assert.equal(400, status)
            assert.equal([[{"upstream_url":"upstream_url is required","request_path":"At least a 'request_host' or a 'request_path' must be specified","request_host":"At least a 'request_host' or a 'request_path' must be specified"}]], stringy.strip(response))

            response, status = http_client.post(BASE_URL, {request_host = "/httpbin", upstream_url = "http://mockbin.com"}, {["content-type"] = content_type})
            assert.equal(400, status)
            assert.equal([[{"request_host":"Invalid value: \/httpbin"}]], stringy.strip(response))
          end
        end)
        it_content_types("should return HTTP 409 if already exists", function(content_type)
          return function()
            local response, status = http_client.post(BASE_URL, {
              request_host = "api-test.com",
              upstream_url = "http://mockbin.com"
            }, {["content-type"] = content_type})
            assert.equal(409, status)
            assert.equal([[{"request_host":"already exists with value 'api-test.com'"}]], stringy.strip(response))
          end
        end)
      end)
    end)

    describe("PUT", function()
      it_content_types("should create if not exists", function(content_type)
        return function()
          local _, status = http_client.put(BASE_URL, {
            name = "new-api",
            request_host = "new-api.com",
            upstream_url = "http://mockbin.com"
          }, {["content-type"] = content_type})
          assert.equal(201, status)
        end
      end)
      it_content_types("#only should not update if some required fields are missing", function(content_type)
        return function()
          local response, status = http_client.put(BASE_URL, {
            id = api.id,
            name = "api-PUT-tests-updated",
            request_host = "updated-api.mockbin.com",
            upstream_url = "http://mockbin.com"
          }, {["content-type"] = content_type})
          assert.equal(400, status)
          local body = json.decode(response)
          assert.equal("created_at is required", body.created_at)
        end
      end)
      it_content_types("#only should update if exists", function(content_type)
        return function()
          local response, status = http_client.put(BASE_URL, {
            id = api.id,
            name = "api-PUT-tests-updated",
            request_host = "updated-api.mockbin.com",
            upstream_url = "http://mockbin.com",
            created_at = 1461276890000
          }, {["content-type"] = content_type})
          assert.equal(200, status)
          local body = json.decode(response)
          assert.equal("api-PUT-tests-updated", body.name)
          assert.truthy(body.created_at)
        end
      end)
      describe("errors", function()
        it_content_types("should return proper validation errors", function(content_type)
          return function()
            local response, status = http_client.put(BASE_URL, {}, {["content-type"] = content_type})
            assert.equal(400, status)
            assert.equal([[{"upstream_url":"upstream_url is required","request_path":"At least a 'request_host' or a 'request_path' must be specified","request_host":"At least a 'request_host' or a 'request_path' must be specified"}]], stringy.strip(response))
          end
        end)
        it_content_types("should return HTTP 409 if already exists", function(content_type)
          -- @TODO this test actually defeats the purpose of PUT. It should probably replace the entity
          return function()
            local response, status = http_client.put(BASE_URL, {
              request_host = "api-test.com",
              upstream_url = "http://mockbin.com"
            }, {["content-type"] = content_type})
            assert.equal(409, status)
            assert.equal([[{"request_host":"already exists with value 'api-test.com'"}]], stringy.strip(response))
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
      it("should retrieve a paginated set", function()
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
        local body_page_3 = json.decode(response)
        assert.truthy(body_page_3.data)
        assert.equal(1, #body_page_3.data)
        assert.equal(10, body_page_3.total)
        assert.falsy(body_page_3.next)
        assert.not_same(body_page_2, body_page_3)
      end)
      it("should refuse invalid filters", function()
        local response, status = http_client.get(BASE_URL, {foo = "bar"})
        assert.equal(400, status)
        assert.equal([[{"foo":"unknown field"}]], stringy.strip(response))
      end)
    end)

    describe("/apis/:api", function()
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
        it("should reply with HTTP 404 if not found", function()
          local _, status = http_client.get(BASE_URL.."none")
          assert.equal(404, status)
        end)
      end)

      describe("PATCH", function()
        it_content_types("should update name if found", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..api.id, {
              name = "patch-updated"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("patch-updated", body.name)

            local api, err = dao_factory.apis:find {id = api.id}
            assert.falsy(err)
            assert.equal("patch-updated", api.name)
          end
        end)
        it_content_types("should update name by its old name", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..api.name, {
              name = "patch-updated"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("patch-updated", body.name)

            local api, err = dao_factory.apis:find {id = api.id}
            assert.falsy(err)
            assert.equal("patch-updated", api.name)
          end
        end)
        it_content_types("should update request_path", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..api.id, {
              request_path = "/httpbin-updated"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("/httpbin-updated", body.request_path)

            local api, err = dao_factory.apis:find {id = api.id}
            assert.falsy(err)
            assert.equal("/httpbin-updated", api.request_path)
          end
        end)
        it_content_types("should update strip_request_path if it was not previously set", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..api.id, {
              strip_request_path = true
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.True(body.strip_request_path)

            local api, err = dao_factory.apis:find {id = api.id}
            assert.falsy(err)
            assert.True(api.strip_request_path)
          end
        end)
        it_content_types("should update request_host and request_path at once", function(content_type)
          return function()
            local response, status = http_client.patch(BASE_URL..api.id, {
              request_path = "/httpbin-updated-path",
              request_host = "httpbin-updated.org"
            }, {["content-type"] = content_type})
            assert.equal(200, status)
            local body = json.decode(response)
            assert.equal("/httpbin-updated-path", body.request_path)
            assert.equal("httpbin-updated.org", body.request_host)

            local api, err = dao_factory.apis:find {id = api.id}
            assert.falsy(err)
            assert.equal("/httpbin-updated-path", api.request_path)
            assert.equal("httpbin-updated.org", api.request_host)
          end
        end)
        describe("errors", function()
          it_content_types("should return 404 if not found", function(content_type)
            return function()
              local _, status = http_client.patch(BASE_URL.."hello", {
                name = "patch-updated"
              }, {["content-type"] = content_type})
              assert.equal(404, status)
            end
          end)
          it_content_types("should return proper validation errors", function(content_type)
            return function()
              local response, status = http_client.patch(BASE_URL..api.id, {
                name = "api",
                request_host = " "
              }, {["content-type"] = content_type})
              assert.equal(400, status)
              assert.equal([[{"request_host":"At least a 'request_host' or a 'request_path' must be specified"}]], stringy.strip(response))
            end
          end)
        end)
      end)

      describe("DELETE", function()
        before_each(function()
          local _, err = dao_factory.apis:insert {
            name = "to-delete",
            request_host = "to-delete.com",
            upstream_url = "http://mockbin.com"
          }
          assert.falsy(err)
        end)
        it("delete an API by id", function()
          local response, status = http_client.delete(BASE_URL..api.id)
          assert.equal(204, status)
          assert.falsy(response)
        end)
        it("delete an API by name", function()
          local response, status = http_client.delete(BASE_URL.."to-delete")
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

      describe("/apis/:api/plugins/", function()
        local PLUGIN_BASE_URL
        local api_with_plugin
        local plugin

        before_each(function()
          PLUGIN_BASE_URL = BASE_URL..api.id.."/plugins/"
          local fixtures = spec_helper.insert_fixtures {
            api = {
              {name = "plugin-put-tests", request_host = "plugin-put-tests.com", upstream_url = "http://mockbin.com"}
            },
            plugin = {
              {name = "key-auth", config = {hide_credentials = true}, __api = 1}
            }
          }
          api_with_plugin = fixtures.api[1]
          plugin = fixtures.plugin[1]
        end)

        describe("POST", function()
          it_content_types("should create a plugin configuration", function(content_type)
            return function()
              local response, status = http_client.post(PLUGIN_BASE_URL, {
                name = "key-auth",
                ["config.key_names"] = "apikey,key"
              }, {["content-type"] = content_type})
              assert.equal(201, status)
              local body = json.decode(response)
              assert.equal("key-auth", body.name)
              assert.truthy(body.config)
              assert.same({"apikey", "key"}, body.config.key_names)
            end
          end)
          it_content_types("should create with default value", function(content_type)
            return function()
              local response, status = http_client.post(PLUGIN_BASE_URL, {
                name = "key-auth"
              }, {["content-type"] = content_type})
              assert.equal(201, status)
              local body = json.decode(response)
              assert.equal("key-auth", body.name)
              assert.truthy(body.config)
              assert.same({"apikey"}, body.config.key_names)
            end
          end)
          describe("errors", function()
            it_content_types("should return proper validation errors", function(content_type)
              return function()
                local response, status = http_client.post(PLUGIN_BASE_URL, {}, {["content-type"] = content_type})
                assert.equal(400, status)
                assert.equal([[{"name":"name is required"}]], stringy.strip(response))
              end
            end)
          end)
        end)

        describe("PUT", function()
          it_content_types("should create if not exists", function(content_type)
            return function()
              local response, status = http_client.put(PLUGIN_BASE_URL, {
                name = "key-auth",
                ["config.key_names"] = "apikey,key"
              }, {["content-type"] = content_type})
              assert.equal(201, status)
              local body = json.decode(response)
              assert.equal("key-auth", body.name)
              assert.truthy(body.config)
              assert.same({"apikey", "key"}, body.config.key_names)
            end
          end)
          it_content_types("should create with default value", function(content_type)
            return function()
              local response, status = http_client.put(PLUGIN_BASE_URL, {
                name = "key-auth"
              }, {["content-type"] = content_type})
              assert.equal(201, status)
              local body = json.decode(response)
              assert.equal("key-auth", body.name)
              assert.truthy(body.config)
              assert.same({"apikey"}, body.config.key_names)
            end
          end)
          it_content_types("should update if exists", function(content_type)
            return function()
              local response, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                name = "key-auth",
                ["config.key_names"] = "updated_apikey",
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)
              local body = json.decode(response)
              assert.truthy(body.config)
              assert.equal("updated_apikey", body.config.key_names[1])
            end
          end)
          it_content_types("should update with default values", function(content_type)
            return function()
              local plugin, err = dao_factory.plugins:insert {
                name = "key-auth",
                api_id = api.id,
                config = {hide_credentials = true}
              }
              assert.falsy(err)
              assert.True(plugin.config.hide_credentials)
              assert.same({"apikey"}, plugin.config.key_names)

              local response, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                name = "key-auth",
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)
              local body = json.decode(response)
              assert.truthy(body.config)
              assert.False(body.config.hide_credentials)

              local plugin, err = dao_factory.plugins:find {
                id = plugin.id,
                name = plugin.name
              }
              assert.falsy(err)
              assert.truthy(plugin.config)
              assert.False(plugin.config.hide_credentials)
              assert.same({"apikey"}, plugin.config.key_names)
            end
          end)
          it_content_types("should update with default values bis", function(content_type)
            return function()
              local plugin, err = dao_factory.plugins:insert {
                name = "rate-limiting",
                api_id = api.id,
                config = {hour = 2}
              }
              assert.falsy(err)
              assert.equal(2, plugin.config.hour)

              local response, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                api_id = api.id,
                name = "rate-limiting",
                ["config.minute"] = 3,
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)
              local body = json.decode(response)
              assert.truthy(body.config)
              assert.falsy(body.config.hour)
              assert.equal(3, body.config.minute)

              local plugin, err = dao_factory.plugins:find {
                id = plugin.id,
                name = plugin.name
              }
              assert.falsy(err)
              assert.truthy(plugin.config)
              assert.falsy(plugin.config.hour)
              assert.equal(3, plugin.config.minute)
            end
          end)
          it_content_types("should override a plugin's `config` if partial", function(content_type)
            return function()
              local response, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                name = "key-auth",
                ["config.key_names"] = "api_key_updated",
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)
              local body = json.decode(response)
              assert.same({"api_key_updated"}, body.config.key_names)
              assert.falsy(body.hide_credentials)
            end
          end)
          it_content_types("should be possible to disable and re-enable it", function(content_type)
            return function()
              local _, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                name = "key-auth",
                enabled = false,
                ["config.key_names"] = "apikey,key",
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)

              local response = http_client.get(PLUGIN_BASE_URL..plugin.id)
              local body = json.decode(response)
              assert.False(body.enabled)

              _, status = http_client.put(PLUGIN_BASE_URL, {
                id = plugin.id,
                name = "key-auth",
                enabled = true,
                ["config.key_names"] = "apikey,key",
                created_at = 1461276890000
              }, {["content-type"] = content_type})
              assert.equal(200, status)

              response = http_client.get(PLUGIN_BASE_URL..plugin.id)
              body = json.decode(response)
              assert.True(body.enabled)
            end
          end)
          describe("errors", function()
            it_content_types("should return proper validation errors", function(content_type)
              return function()
                local response, status = http_client.put(PLUGIN_BASE_URL, {}, {["content-type"] = content_type})
                assert.equal(400, status)
                assert.equal([[{"name":"name is required"}]], stringy.strip(response))
              end
            end)
          end)
        end)

        describe("GET", function()
          it("should retrieve the first page", function()
            local response, status = http_client.get(BASE_URL..api_with_plugin.id.."/plugins/")
            assert.equal(200, status)
            local body = json.decode(response)
            assert.truthy(body.data)
            assert.equal(1, #body.data)
          end)
        end)

        describe("/apis/:api/plugins/:plugin", function()
          local API_PLUGIN_BASE_URL

          before_each(function()
            API_PLUGIN_BASE_URL = BASE_URL..api_with_plugin.id.."/plugins/"
          end)

          describe("GET", function()
            it("should retrieve by id", function()
              local response, status = http_client.get(API_PLUGIN_BASE_URL..plugin.id)
              assert.equal(200, status)
              local body = json.decode(response)
              assert.same(plugin, body)
            end)
            it("[SUCCESS] should not retrieve a plugin that is not associated to the right API", function()
              local response, status = http_client.get(BASE_URL)
              assert.equal(200, status)
              local body = json.decode(response)
              assert.equal(2, body.total)

              local api_id_1 = body.data[1].id
              local api_id_2 = body.data[2].id

              local response, status = http_client.get(spec_helper.API_URL.."/plugins")
              assert.equal(200, status)
              local body = json.decode(response)
              local plugin_id = body.data[1].id

              local _, status = http_client.get(spec_helper.API_URL.."/apis/"..(body.data[1].api_id == api_id_1 and api_id_1 or api_id_2).."/plugins/"..plugin_id)
              assert.equal(200, status)

              -- Let's try to request it with the other API
              local _, status = http_client.get(spec_helper.API_URL.."/apis/"..(body.data[1].api_id == api_id_1 and api_id_2 or api_id_1).."/plugins/"..plugin_id)
              assert.equal(404, status)
            end)
          end)

          describe("PATCH", function()
            it_content_types("should update if exists", function(content_type)
              return function()
                local response, status = http_client.patch(API_PLUGIN_BASE_URL..plugin.id, {
                  ["config.key_names"] = {"key_updated"}
                }, {["content-type"] = content_type})
                assert.equal(200, status)
                local body = json.decode(response)
                assert.same("key_updated", body.config.key_names[1])
              end
            end)
            it_content_types("should not override a plugin's `config` if partial", function(content_type)
              -- This is delicate since a plugin's `config` is a text field in a DB like Cassandra
              return function()
                assert.truthy(plugin.config)
                assert.True(plugin.config.hide_credentials)

                local response, status = http_client.patch(API_PLUGIN_BASE_URL..plugin.id, {
                  ["config.key_names"] = {"key_set_null_test_updated"}
                }, {["content-type"] = content_type})
                assert.equal(200, status)
                local body = json.decode(response)
                assert.same({"key_set_null_test_updated"}, body.config.key_names)
                assert.True(body.config.hide_credentials)
              end
            end)
            it_content_types("should be possible to disable and re-enable it", function(content_type)
              return function()
                local _, status = http_client.patch(API_PLUGIN_BASE_URL..plugin.id, {
                  enabled = false
                }, {["content-type"] = content_type})
                assert.equal(200, status)

                local plugin, err = dao_factory.plugins:find {
                  id = plugin.id,
                  name = plugin.name
                }
                assert.falsy(err)
                assert.False(plugin.enabled)

                _, status = http_client.patch(API_PLUGIN_BASE_URL..plugin.id, {
                  enabled = true
                }, {["content-type"] = content_type})
                assert.equal(200, status)

                plugin, err = dao_factory.plugins:find {
                  id = plugin.id,
                  name = plugin.name
                }
                assert.falsy(err)
                assert.True(plugin.enabled)
              end
            end)
            describe("errors", function()
              it_content_types("should return HTTP 404 if not found", function(content_type)
                return function()
                  local _, status = http_client.patch(API_PLUGIN_BASE_URL.."b6cca0aa-4537-11e5-af97-23a06d98af51", {}, {["content-type"] = content_type})
                  assert.equal(404, status)
                end
              end)
              it_content_types("should return proper validation errors", function(content_type)
                return function()
                  local response, status = http_client.patch(API_PLUGIN_BASE_URL..plugin.id, {
                    name = "foo"
                  }, {["content-type"] = content_type})
                  assert.equal(400, status)
                  assert.equal([[{"config":"Plugin \"foo\" not found"}]], stringy.strip(response))
                end
              end)
            end)
          end)

          describe("DELETE", function()
            it("should delete a plugin configuration", function()
              local response, status = http_client.delete(API_PLUGIN_BASE_URL..plugin.id)
              assert.equal(204, status)
              assert.falsy(response)
            end)
            describe("errors", function()
              it("should return HTTP 404 if not found", function()
                local _, status = http_client.delete(API_PLUGIN_BASE_URL.."b6cca0aa-4537-11e5-af97-23a06d98af51")
                assert.equal(404, status)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end)