local helpers = require "spec.helpers"
local cjson = require "cjson"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title.." with application/www-form-urlencoded", test_form_encoded)
  it(title.." with application/json", test_json)
end

describe("Admin API", function()
  local client
  setup(function()
    helpers.dao:truncate_tables()
    helpers.execute "pkill nginx; pkill serf"
    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())

    client = assert(helpers.http_client("127.0.0.1", helpers.admin_port))
  end)
  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  describe("/apis", function()
    describe("POST", function()
      before_each(function()
        helpers.dao:truncate_tables()
      end)
      it_content_types("creates an API", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              name = "my-api",
              request_host = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.equal("my.api.com", json.request_host)
          assert.equal("http://api.com", json.upstream_url)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_nil(json.request_path)
          assert.False(json.preserve_host)
          assert.False(json.strip_request_path)
        end
      end)
      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/apis",
            body = '{"hello": "world"',
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            assert.equal([[{"upstream_url":"upstream_url is required",]]
                         ..[["request_path":"At least a 'request_host' or a]]
                         ..[[ 'request_path' must be specified","request_host":]]
                         ..[["At least a 'request_host' or a 'request_path']]
                         ..[[ must be specified"}]], body)

            -- Invalid parameter
            res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                request_host = "my-api",
                upstream_url = "http://my-api.con"
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            assert.equal([[{"request_host":"Invalid value: my-api"}]], body)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                name = "my-api",
                request_host = "my-api.com",
                upstream_url = "http://my-api.com"
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                name = "my-api",
                request_host = "my-api2.com",
                upstream_url = "http://my-api2.com"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            assert.equal([[{"name":"already exists with value 'my-api'"}]], body)
          end
        end)
      end)
    end)

    describe("PUT", function()
      before_each(function()
        helpers.dao:truncate_tables()
      end)

      it_content_types("#o creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/apis",
            body = {
              name = "my-api",
              request_host = "my.api.com",
              upstream_url = "http://my-api.com",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.equal("my.api.com", json.request_host)
          assert.equal("http://my-api.com", json.upstream_url)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_nil(json.request_path)
          assert.False(json.preserve_host)
          assert.False(json.strip_request_path)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              name = "my-api",
              request_host = "my.api.com",
              upstream_url = "http://my-api.com"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
            method = "PUT",
            path = "/apis",
            body = {
              id = json.id,
              name = "my-new-api",
              request_host = "my-new-api.com",
              upstream_url = "http://my-api.com",
              created_at = json.created_at
            },
            headers = {["Content-Type"] = content_type}
          })
          body = assert.res_status(200, res)
          local updated_json = cjson.decode(body)
          assert.equal("my-new-api", updated_json.name)
          assert.equal("my-new-api.com", updated_json.request_host)
          assert.equal(json.upstream_url, updated_json.upstream_url)
          assert.equal(json.id, updated_json.id)
          assert.equal(json.created_at, updated_json.created_at)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "PUT",
              path = "/apis",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            assert.equal([[{"upstream_url":"upstream_url is required",]]
                         ..[["request_path":"At least a 'request_host' or a]]
                         ..[[ 'request_path' must be specified","request_host":]]
                         ..[["At least a 'request_host' or a 'request_path']]
                         ..[[ must be specified"}]], body)

            -- Invalid parameter
            res = assert(client:send {
              method = "PUT",
              path = "/apis",
              body = {
                request_host = "my-api",
                upstream_url = "http://my-api.com",
                created_at = 1461276890000
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            assert.equal([[{"request_host":"Invalid value: my-api"}]], body)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            -- @TODO this particular test actually defeats the purpose of PUT.
            -- It should probably replace the entity
            local res = assert(client:send {
                method = "PUT",
                path = "/apis",
                body = {
                  name = "my-api",
                  request_host = "my-api.com",
                  upstream_url = "http://my-api.com",
                  created_at = 1461276890000
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(201, res)
              local json = cjson.decode(body)

              res = assert(client:send {
                method = "PUT",
                path = "/apis",
                body = {
                  name = "my-api",
                  request_host = "my-api2.com",
                  upstream_url = "http://my-api2.com",
                  created_at = json.created_at
                },
                headers = {["Content-Type"] = content_type}
              })
              body = assert.res_status(409, res)
              assert.equal([[{"name":"already exists with value 'my-api'"}]], body)
            end
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        helpers.dao:truncate_tables()

        for i = 1, 10 do
          assert(helpers.dao.apis:insert {
            name = "api-"..i,
            request_path = "/api-"..i,
            upstream_url = "http://my-api.com"
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_tables()
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/apis"
        })
        local res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(10, #json.data)
        assert.equal(10, json.total)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/apis",
            query = {size = 3, offset = offset}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(10, json.total)

          if i < 4 then
            assert.equal(3, #json.data)
          else
            assert.equal(1, #json.data)
          end

          if i > 1 then
            -- check all pages are different
            assert.not_same(pages[i-1], json)
          end

          offset = json.offset
          pages[i] = json
        end
      end)
      it("handles invalid filters", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis",
            query = {foo = "bar"}
          })
          local body = assert.res_status(400, res)
          assert.equal([[{"foo":"unknown field"}]], body)
      end)
    end)

    describe("/apis/{api}", function()
      local api
      setup(function()
        helpers.dao:truncate_tables()
      end)
      before_each(function()
        api = assert(helpers.dao.apis:insert {
          name = "my-api",
          request_path = "/my-api",
          upstream_url = "http://my-api.com"
        })
      end)
      after_each(function()
        helpers.dao:truncate_tables()
      end)

      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/"..api.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(api, json)
        end)
        it("retrieves by name", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/"..api.name
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(api, json)
        end)
        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/_inexistent_"
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates if found", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id,
              body = {
                name = "my-updated-api"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("my-updated-api", json.name)
            assert.equal(api.id, json.id)

            local in_db = assert(helpers.dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates a name from a name in path", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.name,
              body = {
                name = "my-updated-api"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("my-updated-api", json.name)
            assert.equal(api.id, json.id)

            local in_db = assert(helpers.dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates request_path", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id,
              body = {
                request_path = "/my-updated-api"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("/my-updated-api", json.request_path)
            assert.equal(api.id, json.id)

            local in_db = assert(helpers.dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates strip_request_path if not previously set", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id,
              body = {
                strip_request_path = true
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.True(json.strip_request_path)
            assert.equal(api.id, json.id)

            local in_db = assert(helpers.dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates multiple fields at once", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id,
              body = {
               request_path = "/my-updated-path",
               request_host = "my-updated.tld"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("/my-updated-path", json.request_path)
            assert.equal("my-updated.tld", json.request_host)
            assert.equal(api.id, json.id)

            local in_db = assert(helpers.dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end)
        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/apis/_inexistent_",
                body = {
                 request_path = "/my-updated-path"
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.res_status(404, res)
            end
          end)
          it_content_types("handles invalid input", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/apis/"..api.id,
                body = {
                 upstream_url = "api.com"
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(400, res)
              assert.equal([[{"upstream_url":"upstream_url is not a url"}]], body)
            end
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes an API by id", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/apis/"..api.id
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        it("deletes an API by name", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/apis/"..api.name
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        describe("error", function()
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/apis/_inexistent_"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)

  describe("/apis/{api}/plugins", function()
    local api
    setup(function()
      helpers.dao:truncate_tables()

      api = assert(helpers.dao.apis:insert {
        name = "my-api",
        request_path = "/my-api",
        upstream_url = "http://my-api.com"
      })
    end)
    before_each(function()
      helpers.dao.plugins:truncate()
    end)

    describe("POST", function()
      it_content_types("creates a plugin config", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis/"..api.id.."/plugins",
            body = {
              name = "key-auth",
              ["config.key_names"] = "apikey,key"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("key-auth", json.name)
          assert.same({"apikey", "key"}, json.config.key_names)
        end
      end)
      it_content_types("references API by name too", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis/"..api.name.."/plugins",
            body = {
              name = "key-auth",
              ["config.key_names"] = "apikey,key"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("key-auth", json.name)
          assert.same({"apikey", "key"}, json.config.key_names)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/apis/"..api.id.."/plugins",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            assert.equal([[{"name":"name is required"}]], body)
          end
        end)
      end)
    end)

    describe("PUT", function()
      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              name = "key-auth",
              ["config.key_names"] = "apikey,key",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("key-auth", json.name)
          assert.same({"apikey", "key"}, json.config.key_names)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              name = "key-auth",
              ["config.key_names"] = "apikey,key",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              id = json.id,
              name = "key-auth",
              ["config.key_names"] = "key",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          body = assert.res_status(200, res)
          json = cjson.decode(body)
          assert.equal("key-auth", json.name)
          assert.same({"key"}, json.config.key_names)
        end
      end)
      it_content_types("perfers default values when replacing", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "key-auth",
            api_id = api.id,
            config = {hide_credentials = true}
          })
          assert.True(plugin.config.hide_credentials)
          assert.same({"apikey"}, plugin.config.key_names)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              id = plugin.id,
              name = "key-auth",
              ["config.key_names"] = "apikey,key",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.False(json.config.hide_credentials) -- not true anymore

          plugin = assert(helpers.dao.plugins:find {
            id = plugin.id,
            name = plugin.name
          })
          assert.False(plugin.config.hide_credentials)
          assert.same({"apikey", "key"}, plugin.config.key_names)
        end
      end)
      it_content_types("overrides a plugin previous config if partial", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "key-auth",
            api_id = api.id
          })
          assert.same({"apikey"}, plugin.config.key_names)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              id = plugin.id,
              name = "key-auth",
              ["config.key_names"] = "apikey,key",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({"apikey", "key"}, json.config.key_names)
        end
      end)
      it_content_types("updates the enabled property", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "key-auth",
            api_id = api.id
          })
          assert.True(plugin.enabled)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/"..api.id.."/plugins",
            body = {
              id = plugin.id,
              name = "key-auth",
              enabled = false,
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.False(json.enabled)

          plugin = assert(helpers.dao.plugins:find {
            id = plugin.id,
            name = plugin.name
          })
          assert.False(plugin.enabled)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PUT",
              path = "/apis/"..api.id.."/plugins",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            assert.equal([[{"name":"name is required"}]], body)
          end
        end)
      end)
    end)

    describe("GET", function()
      it("retrieves the first page", function()
        assert(helpers.dao.plugins:insert {
          name = "key-auth",
          api_id = api.id
        })

        local res = assert(client:send {
          method = "GET",
          path = "/apis/"..api.id.."/plugins"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
      end)
    end)

    describe("/apis/{api}/plugins/{plugin}", function()
      local plugin
      before_each(function()
        plugin = assert(helpers.dao.plugins:insert {
          name = "key-auth",
          api_id = api.id
        })
      end)

      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/"..api.id.."/plugins/"..plugin.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(plugin, json)
        end)
        it("only retrieves if associated to the correct API", function()
          -- Create an API and try to query our plugin through it
          local w_api = assert(helpers.dao.apis:insert {
            name = "wrong-api",
            request_path = "/wrong-api",
            upstream_url = "http://wrong-api.com"
          })

          -- Try to request the plugin through it (belongs to the fixture API instead)
          local res = assert(client:send {
            method = "GET",
            path = "/apis/"..w_api.id.."/plugins/"..plugin.id
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates if found", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id.."/plugins/"..plugin.id,
              body = {
                ["config.key_names"] = {"key-updated"}
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({"key-updated"}, json.config.key_names)
            assert.equal(plugin.id, json.id)

            local in_db = assert(helpers.dao.plugins:find {
              id = plugin.id,
              name = plugin.name
            })
            assert.same(json, in_db)
          end
        end)
        it_content_types("doesn't override a plugin config if partial", function(content_type)
          -- This is delicate since a plugin config is a text field in a DB like Cassandra
          return function()
            plugin = assert(helpers.dao.plugins:update({
              config = {hide_credentials = true}
            }, {id = plugin.id, name = plugin.name}))
            assert.True(plugin.config.hide_credentials)
            assert.same({"apikey"}, plugin.config.key_names)

            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id.."/plugins/"..plugin.id,
              body = {
                ["config.key_names"] = {"my-new-key"}
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.True(json.config.hide_credentials) -- still true
            assert.same({"my-new-key"}, json.config.key_names)

            plugin = assert(helpers.dao.plugins:find {
              id = plugin.id,
              name = plugin.name
            })
            assert.True(plugin.config.hide_credentials) -- still true
            assert.same({"my-new-key"}, plugin.config.key_names)
          end
        end)
        it_content_types("updates the enabled property", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/"..api.id.."/plugins/"..plugin.id,
              body = {
                name = "key-auth",
                enabled = false
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            plugin = assert(helpers.dao.plugins:find {
              id = plugin.id,
              name = plugin.name
            })
            assert.False(plugin.enabled)
          end
        end)
        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/apis/"..api.id.."/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51",
                body = {},
                headers = {["Content-Type"] = content_type}
              })
              assert.res_status(404, res)
            end
          end)
          it_content_types("handles invalid input", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/apis/"..api.id.."/plugins/"..plugin.id,
                body = {
                  name = "foo"
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(400, res)
              assert.equal([[{"config":"Plugin \"foo\" not found"}]], body)
            end
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes a plugin configuration", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/apis/"..api.id.."/plugins/"..plugin.id
          })
          assert.res_status(204, res)
        end)
        describe("errors", function()
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/apis/"..api.id.."/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end)
