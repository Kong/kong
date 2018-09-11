local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"

local dao_helpers = require "spec.02-integration.03-dao.helpers"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

dao_helpers.for_each_dao(function(kong_config)

pending("Admin API #" .. kong_config.database, function()
  local client
  local dao
  local db

  setup(function()
    local _
    _, db, dao = helpers.get_db_utils(kong_config.database, {})

    assert(helpers.start_kong{
      database = kong_config.database
    })
  end)

  teardown(function()
    helpers.stop_kong()
    dao:truncate_table("apis")
    db:truncate("plugins")
    db:truncate("routes")
    db:truncate("services")
  end)

  before_each(function()
    dao:truncate_table("apis")
    db:truncate("plugins")
    db:truncate("routes")
    db:truncate("services")
  end)

  describe("/apis", function()
    describe("POST", function()

      it_content_types("creates an API", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              name = "my-api",
              hosts = "my.api.com",
              upstream_url = "http://api.com"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.same({ "my.api.com" }, json.hosts)
          assert.equal("http://api.com", json.upstream_url)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_nil(json.paths)
          assert.False(json.preserve_host)
          assert.True(json.strip_uri)
          assert.equals(5, json.retries)
        end
      end)

      it_content_types("creates an API with complex routing", function(content_type)
        return function()
          local res = assert(client:send {
            method  = "POST",
            path    = "/apis",
            body    = {
              name         = "my-api",
              upstream_url = helpers.mock_upstream_url,
              methods      = "GET,POST,PATCH",
              hosts        = "foo.api.com,bar.api.com",
              uris         = "/foo,/bar",
            },
            headers = { ["Content-Type"] = content_type }
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
          assert.same({ "/foo","/bar" }, json.uris)
          assert.same({ "GET", "POST", "PATCH" }, json.methods)
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
            local json = cjson.decode(body)
            assert.same({
              name = "name is required",
              upstream_url = "upstream_url is required"
            }, json)

            -- Invalid parameter
            res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                name = "my-api",
                hosts = "my-api.com/com",
                upstream_url = "http://my-api.con"
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hosts = "host with value 'my-api.com/com' is invalid: Invalid hostname" }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                name = "my-api",
                hosts = "my-api.com",
                upstream_url = "http://my-api.com"
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            client = assert(helpers.admin_client())

            res = assert(client:send {
              method = "POST",
              path = "/apis",
              body = {
                name = "my-api",
                hosts = "my-api2.com",
                upstream_url = "http://my-api2.com"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({name = "already exists with value 'my-api'" }, json)
          end
        end)
      end)
    end)

    describe("PUT", function()

      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/apis",
            body = {
              name = "my-api",
              upstream_url = "http://my-api.com",
              hosts = "my.api.com",
              created_at = 1461276890000,
              retries = 0,
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("my-api", json.name)
          assert.same({ "my.api.com" }, json.hosts)
          assert.equal("http://my-api.com", json.upstream_url)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_nil(json.paths)
          assert.False(json.preserve_host)
          assert.True(json.strip_uri)
          assert.equals(0, json.retries)
        end
      end)
      it_content_types("returns 404 when specifying non-existent primary key values", function(content_type)
        -- Note: while not an appropriate behavior for PUT, our current
        -- behavior for this method is the following:
        -- 1. if the payload does not have the entity's primary key values,
        --    we attempt an insert()
        -- 2. if the payload has primary key values, we attempt an update()
        --
        -- This is a regression added after investigating the following issue:
        --     https://github.com/Kong/kong/issues/2774
        --
        -- Eventually, our Admin endpoint will follow a more appropriate
        -- behavior for PUT.
        local res = assert(helpers.admin_client():send {
          method = "PUT",
          path = "/apis",
          body = {
            id = utils.uuid(),
            name = "my-api",
            hosts = "my.api.com",
            created_at = 1461276890000,
            upstream_url = "http://my-api.com",
          },
          headers = { ["Content-Type"] = content_type },
        })
        assert.res_status(404, res)
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/apis",
            body = {
              name = "my-api",
              hosts = "my.api.com",
              upstream_url = "http://my-api.com"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          client = assert(helpers.admin_client())

          res = assert(client:send {
            method = "PUT",
            path = "/apis",
            body = {
              id = json.id,
              name = "my-new-api",
              hosts = "my-new-api.com",
              upstream_url = "http://my-api.com",
              created_at = json.created_at,
              retries = 99,
            },
            headers = {["Content-Type"] = content_type}
          })
          body = assert.res_status(200, res)
          local updated_json = cjson.decode(body)
          assert.equal("my-new-api", updated_json.name)
          assert.same({ "my-new-api.com" }, updated_json.hosts)
          assert.equal(json.upstream_url, updated_json.upstream_url)
          assert.equal(json.id, updated_json.id)
          assert.equal(json.created_at, updated_json.created_at)
          assert.equal(99, updated_json.retries)
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
            local json = cjson.decode(body)
            assert.same({
              name = "name is required",
              upstream_url = "upstream_url is required"
            }, json)

            client = assert(helpers.admin_client())

            -- Invalid parameter
            res = assert(client:send {
              method = "PUT",
              path = "/apis",
              body = {
                name = "my-api",
                upstream_url = "http://my-api.com",
                hosts = "my-api.com/com",
                created_at = 1461276890000
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hosts = "host with value 'my-api.com/com' is invalid: Invalid hostname" }, json)
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
                  hosts = "my-api.com",
                  upstream_url = "http://my-api.com",
                  created_at = 1461276890000
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(201, res)
              local json = cjson.decode(body)

              client = assert(helpers.admin_client())

              res = assert(client:send {
                method = "PUT",
                path = "/apis",
                body = {
                  name = "my-api",
                  hosts = "my-api2.com",
                  upstream_url = "http://my-api2.com",
                  created_at = json.created_at
                },
                headers = {["Content-Type"] = content_type}
              })
              body = assert.res_status(409, res)
              local json = cjson.decode(body)
              assert.same({ name = "already exists with value 'my-api'" }, json)
            end
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        for i = 1, 10 do
          assert(dao.apis:insert {
            name = "api-" .. i,
            uris = "/api-" .. i,
            upstream_url = "http://my-api.com"
          })
        end
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          method = "GET",
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
          local res = assert(helpers.admin_client():send {
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
          local json = cjson.decode(body)
          assert.same({ foo = "unknown field" }, json)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/apis",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)

      describe("empty results", function()
        it("data property is an empty array", function()
          dao:truncate_table("apis")

          local res = assert(client:send {
            method = "GET",
            path = "/apis"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ data = {}, total = 0 }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      before_each(function()
        dao:truncate_table("apis")
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it("returns 405 on invalid method", function()
        local methods = {"DELETE"}
        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/apis",
            body = {}, -- tmp: body to allow POST/PUT to work
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)
    end)
  end)

  describe("/apis/{api}", function()
    local api

    before_each(function()
      dao:truncate_table("apis")
      api = assert(dao.apis:insert {
        name = "my-api",
        uris = "/my-api",
        upstream_url = "http://my-api.com"
      })
    end)

    describe("GET", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it("retrieves by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/apis/" .. api.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(api, json)
      end)
      it("retrieves by name", function()
        local res = assert(client:send {
          method = "GET",
          path = "/apis/" .. api.name
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
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/apis/" .. api.id,
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("PATCH", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it_content_types("updates if found", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/apis/" .. api.id,
            body = {
              name = "my-updated-api"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("my-updated-api", json.name)
          assert.equal(api.id, json.id)

          local in_db = assert(dao.apis:find {id = api.id})
          assert.same(json, in_db)
        end
      end)
      it_content_types("updates a name from a name in path", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/apis/" .. api.name,
            body = {
              name = "my-updated-api"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("my-updated-api", json.name)
          assert.equal(api.id, json.id)

          local in_db = assert(dao.apis:find {id = api.id})
          assert.same(json, in_db)
        end
      end)
      it_content_types("updates uris", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/apis/" .. api.id,
            body = {
              uris = "/my-updated-api,/my-new-uri"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ "/my-updated-api", "/my-new-uri" }, json.uris)
          assert.equal(api.id, json.id)

          local in_db = assert(dao.apis:find {id = api.id})
          assert.same(json, in_db)
        end
      end)
      it_content_types("updates strip_uri if not previously set", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/apis/" .. api.id,
            body = {
              strip_uri = true
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.True(json.strip_uri)
          assert.equal(api.id, json.id)

          local in_db = assert(dao.apis:find {id = api.id})
          assert.same(json, in_db)
        end
      end)
      it_content_types("updates multiple fields at once", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/apis/" .. api.id,
            body = {
              uris = "/my-updated-path",
              hosts = "my-updated.tld"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ "/my-updated-path" }, json.uris)
          assert.same({ "my-updated.tld" }, json.hosts)
          assert.equal(api.id, json.id)

          local in_db = assert(dao.apis:find {id = api.id})
          assert.same(json, in_db)
        end
      end)
      it_content_types("removes optional field with ngx.null", function(content_type)
        return function()
          -- TODO: how should ngx.null work with application/www-form-urlencoded?
          if content_type == "application/json" then
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/" .. api.id,
              body = {
                uris = ngx.null,
                hosts = ngx.null,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.is_nil(json.uris)
            assert.is_nil(json.hosts)
            assert.equal(api.id, json.id)

            local in_db = assert(dao.apis:find {id = api.id})
            assert.same(json, in_db)
          end
        end
      end)

      describe("errors", function()
        it_content_types("returns 404 if not found", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/_inexistent_",
              body = {
               uris = "/my-updated-path"
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
              path = "/apis/" .. api.id,
              body = {
                upstream_url = "api.com"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ upstream_url = "upstream_url is not a url" }, json)
          end
        end)
      end)
    end)

    describe("DELETE", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it("deletes an API by id", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/apis/" .. api.id
        })
        local body = assert.res_status(204, res)
        assert.equal("", body)
      end)
      it("deletes an API by name", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/apis/" .. api.name
        })
        local body = assert.res_status(204, res)
        assert.equal("", body)
      end)
      describe("errors", function()
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

  -- marking as pending as plugins don't have an api_id any more.
  -- Might need to revisit these specs if we end up implementing the sugar method for apis
  pending("/apis/{api}/plugins", function()
    local api
    before_each(function()
      api = assert(dao.apis:insert {
        name = "my-api",
        uris = "/my-api",
        upstream_url = "http://my-api.com"
      })
    end)

    describe("POST", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it_content_types("creates a plugin config", function(content_type)
        return function()
          local inputs = {
            ["application/x-www-form-urlencoded"] = {
              name = "key-auth",
              ["config.key_names[1]"] = "apikey",
              ["config.key_names[2]"] = "key",
            },
            ["application/json"] = {
              name = "key-auth",
              config = {
                key_names = { "apikey", "key" },
              }
            },
          }
          local res = assert(client:send {
            method = "POST",
            path = "/apis/" .. api.id .. "/plugins",
            body = inputs[content_type],
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
            path = "/apis/" .. api.name .. "/plugins",
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
        before_each(function()
          client = assert(helpers.admin_client())
        end)
        after_each(function()
          if client then client:close() end
        end)
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/apis/" .. api.id .. "/plugins",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            -- insert initial plugin
            local res = assert(client:send {
              method = "POST",
              path = "/apis/" .. api.id .. "/plugins",
              body = {
                name="basic-auth",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(201)
            assert.response(res).has.jsonbody()

            -- do it again, to provoke the error
            local res = assert(client:send {
              method = "POST",
              path = "/apis/" .. api.id .. "/plugins",
              body = {
                name="basic-auth",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(409)
            local json = assert.response(res).has.jsonbody()
            assert.same({ name = "already exists with value 'basic-auth'"}, json)
          end
        end)
        it_content_types("returns 409 on id conflict #xxx", function(content_type)
          return function()
            -- insert initial plugin
            local res = assert(client:send {
              method = "POST",
              path = "/apis/"..api.id.."/plugins",
              body = {
                name="basic-auth",
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(201, res)
            local plugin = cjson.decode(body)

            -- do it again, to provoke the error
            local conflict_res = assert(client:send {
              method = "POST",
              path = "/apis/"..api.id.."/plugins",
              body = {
                name="key-auth",
                id = plugin.id,
              },
              headers = {["Content-Type"] = content_type}
            })
            local conflict_body = assert.res_status(409, conflict_res)
            local json = cjson.decode(conflict_body)
            assert.same({ id = "already exists with value '" .. plugin.id .. "'"}, json)
          end
        end)
      end)
    end)

    describe("PUT", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/apis/" .. api.id .. "/plugins",
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
            path = "/apis/" .. api.id .. "/plugins",
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
            path = "/apis/" .. api.id .. "/plugins",
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
          local plugin = assert(dao.plugins:insert {
            name = "key-auth",
            api = { id = api.id },
            config = {hide_credentials = true}
          })
          assert.True(plugin.config.hide_credentials)
          assert.same({"apikey"}, plugin.config.key_names)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/" .. api.id .. "/plugins",
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

          plugin = assert(dao.plugins:find {
            id = plugin.id,
            name = plugin.name
          })
          assert.False(plugin.config.hide_credentials)
          assert.same({"apikey", "key"}, plugin.config.key_names)
        end
      end)
      it_content_types("overrides a plugin previous config if partial", function(content_type)
        return function()
          local plugin = assert(dao.plugins:insert {
            name = "key-auth",
            api = { id = api.id },
          })
          assert.same({"apikey"}, plugin.config.key_names)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/" .. api.id .. "/plugins",
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
          local plugin = assert(dao.plugins:insert {
            name = "key-auth",
            api = { id = api.id },
          })
          assert.True(plugin.enabled)

          local res = assert(client:send {
            method = "PUT",
            path = "/apis/" .. api.id .. "/plugins",
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

          plugin = assert(dao.plugins:find {
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
              path = "/apis/" .. api.id .. "/plugins",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)
          end
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        client = assert(helpers.admin_client())
      end)
      after_each(function()
        if client then client:close() end
      end)

      it("retrieves the first page", function()
        assert(dao.plugins:insert {
          name = "key-auth",
          api = { id = api.id },
        })
        local res = assert(client:send {
          method = "GET",
          path = "/apis/" .. api.id .. "/plugins"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/apis/" .. api.id .. "/plugins",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("/apis/{api}/plugins/{plugin}", function()
      local plugin
      before_each(function()
        plugin = assert(dao.plugins:insert {
          name = "key-auth",
          api = { id = api.id },
        })
      end)

      describe("GET", function()
        before_each(function()
          client = assert(helpers.admin_client())
        end)
        after_each(function()
          if client then client:close() end
        end)

        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/" .. api.id .. "/plugins/" .. plugin.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(plugin, json)
        end)
        it("only retrieves if associated to the correct API", function()
          -- Create an API and try to query our plugin through it
          local w_api = assert(dao.apis:insert {
            name = "wrong-api",
            uris = "/wrong-api",
            upstream_url = "http://wrong-api.com"
          })

          -- Try to request the plugin through it (belongs to the fixture API instead)
          local res = assert(client:send {
            method = "GET",
            path = "/apis/" .. w_api.id .. "/plugins/" .. plugin.id
          })
          assert.res_status(404, res)
        end)
        it("ignores an invalid body", function()
          local res = assert(client:send {
            method = "GET",
            path = "/apis/" .. api.id .. "/plugins/" .. plugin.id,
            body = "this fails if decoded as json",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })
          assert.res_status(200, res)
        end)
      end)

      describe("PATCH", function()
        before_each(function()
          client = assert(helpers.admin_client())
        end)
        after_each(function()
          if client then client:close() end
        end)

        it_content_types("updates if found", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/" .. api.id .. "/plugins/" .. plugin.id,
              body = {
                ["config.key_names"] = {"key-updated"}
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({"key-updated"}, json.config.key_names)
            assert.equal(plugin.id, json.id)

            local in_db = assert(dao.plugins:find {
              id = plugin.id,
              name = plugin.name
            })
            assert.same(json, in_db)
          end
        end)
        it_content_types("doesn't override a plugin config if partial", function(content_type)
          -- This is delicate since a plugin config is a text field in a DB like Cassandra
          return function()
            plugin = assert(dao.plugins:update({
              config = {hide_credentials = true}
            }, {id = plugin.id, name = plugin.name}))
            assert.True(plugin.config.hide_credentials)
            assert.same({"apikey"}, plugin.config.key_names)

            local res = assert(client:send {
              method = "PATCH",
              path = "/apis/" .. api.id .. "/plugins/" .. plugin.id,
              body = {
                ["config.key_names"] = {"my-new-key"}
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.True(json.config.hide_credentials) -- still true
            assert.same({"my-new-key"}, json.config.key_names)

            plugin = assert(dao.plugins:find {
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
              path = "/apis/" .. api.id .. "/plugins/" .. plugin.id,
              body = {
                name = "key-auth",
                enabled = false
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            plugin = assert(dao.plugins:find {
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
                path = "/apis/" .. api.id .. "/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51",
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
                path = "/apis/" .. api.id .. "/plugins/" .. plugin.id,
                body = {
                  name = "foo"
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({ config = "plugin 'foo' not enabled; add it to the 'plugins' configuration property" }, json)
            end
          end)
        end)
      end)

      describe("DELETE", function()
        before_each(function()
          client = assert(helpers.admin_client())
        end)
        after_each(function()
          if client then client:close() end
        end)

        it("deletes a plugin configuration", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/apis/" .. api.id .. "/plugins/" .. plugin.id
          })
          assert.res_status(204, res)
        end)
        describe("errors", function()
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/apis/" .. api.id .. "/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end)

describe("Admin API request size", function()
  local client

  setup(function()
    assert(helpers.get_db_utils(kong_config.database, {
      "apis",
      "plugins",
      "routes",
      "services",
    }))
    assert(helpers.start_kong{
      database = kong_config.database
    })
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = assert(helpers.admin_client())
  end)
  after_each(function()
    if client then client:close() end
  end)

  it("handles req bodies < 10MB", function()
    local host = "host-000000000000000"
    local n = 2^20 / #host
    local buf = {}
    for i = 1, n do buf[#buf+1] = ("host-%015d"):format(i) end
    local hosts = table.concat(buf, ",")

    local res = assert(client:post("/apis/", {
      body = {
        name = "my-api-under-10",
        hosts = hosts,
        upstream_url = "http://api.com",
      },
      headers = {["Content-Type"] = "application/json"}
    }))
    assert.res_status(201, res)
  end)

  it("fails with req bodies 10MB", function()
    local host = "host-000000000000000"
    local n = 11 * 2^20 / #host
    local buf = {}
    for i = 1, n do buf[#buf+1] = ("host-%015d"):format(i) end
    local hosts = table.concat(buf, ",")

    local res = assert(client:post("/apis/", {
      body = {
        name = "my-api-10",
        hosts = hosts,
        upstream_url = "http://api.com",
      },
      headers = {["Content-Type"] = "application/json"}
    }))
    assert.res_status(413, res)
  end)
end)
end)
