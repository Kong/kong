local helpers = require "spec.helpers"
local dao_helpers = require "spec.02-integration.03-dao.helpers"
local cjson = require "cjson"
local DAOFactory = require "kong.dao.factory"

local slots_default, slots_max = 100, 2^16

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

dao_helpers.for_each_dao(function(kong_config)

describe("Admin API: #" .. kong_config.database, function()
  local client
  local dao

  setup(function()
    dao = assert(DAOFactory.new(kong_config))
    helpers.run_migrations(dao)

    helpers.run_migrations(dao)
    assert(helpers.start_kong{
      database = kong_config.database
    })
    client = assert(helpers.admin_client())
  end)

  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
  end)

  describe("/upstreams #" .. kong_config.database, function()
    describe("POST", function()
      before_each(function()
        dao:truncate_tables()
      end)
      it_content_types("creates an upstream with defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_default, json.slots)
          assert.are.equal("none", json.hash_on)
          assert.are.equal("none", json.hash_fallback)
          assert.is_nil(json.hash_on_header)
          assert.is_nil(json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream without defaults", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = 10,
              hash_on = "consumer",
              hash_fallback = "ip",
              hash_on_header = "HeaderName",
              hash_fallback_header = "HeaderFallback",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(10, json.slots)
          assert.are.equal("consumer", json.hash_on)
          assert.are.equal("ip", json.hash_fallback)
          assert.are.equal("HeaderName", json.hash_on_header)
          assert.are.equal("HeaderFallback", json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream with 2 header hashes", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = 10,
              hash_on = "header",
              hash_fallback = "header",
              hash_on_header = "HeaderName1",
              hash_fallback_header = "HeaderName2",
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(10, json.slots)
          assert.are.equal("header", json.hash_on)
          assert.are.equal("header", json.hash_fallback)
          assert.are.equal("HeaderName1", json.hash_on_header)
          assert.are.equal("HeaderName2", json.hash_fallback_header)
        end
      end)
      it_content_types("creates an upstream with " .. slots_max .. " slots", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my.upstream",
              slots = slots_max,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my.upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.are.equal(slots_max, json.slots)
        end
      end)
      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/upstreams",
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
              path = "/upstreams",
              body = {
                slots = 50,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)

            -- Invalid name parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "some invalid host name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Invalid name; must be a valid hostname" }, json)

            -- Invalid slots parameter
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                slots = 2^16+1
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "number of slots must be between 10 and 65536" }, json)

            -- Invalid hash_on entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "something that is invalid",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hash_on = '"something that is invalid" is not allowed. Allowed values are: "none", "consumer", "ip", "header"' }, json)

            -- Invalid hash_fallback entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "something that is invalid",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ hash_fallback = '"something that is invalid" is not allowed. Allowed values are: "none", "consumer", "ip", "header"' }, json)

            -- same hash entries
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "consumer",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot set fallback and primary hashes to the same value" }, json)

            -- Invalid header
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "consumer",
                hash_on_header = "not a <> valid <> header name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Header: bad header name 'not a <> valid <> header name', allowed characters are A-Z, a-z, 0-9, '_', and '-'" }, json)

            -- Invalid header
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "header",
                hash_fallback_header = "not a <> valid <> header name",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Header: bad header name 'not a <> valid <> header name', allowed characters are A-Z, a-z, 0-9, '_', and '-'" }, json)

            -- Same headers
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "header",
                hash_on_header = "headername",
                hash_fallback_header = "HeaderName",  --> validate case insensitivity
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot set fallback and primary hashes to the same value" }, json)

            -- No headername provided
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "header",
                hash_fallback = "header",
                hash_on_header = nil,  -- not given
                hash_fallback_header = "HeaderName",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Hashing on 'header', but no header name provided" }, json)

            -- No fallback headername provided
            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
                hash_on = "consumer",
                hash_fallback = "header",
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Hashing on 'header', but no header name provided" }, json)

          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            res = assert(client:send {
              method = "POST",
              path = "/upstreams",
              body = {
                name = "my.upstream",
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ name = "already exists with value 'my.upstream'" }, json)
          end
        end)
      end)
    end)

    describe("PUT", function()
      before_each(function()
        dao:truncate_tables()
      end)

      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()
          assert.equal("my-upstream", json.name)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
          assert.is_number(json.slots)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "PUT",
            path = "/upstreams",
            body = {
              id = json.id,
              name = "my-new-upstream",
              slots = 123,
              created_at = json.created_at
            },
            headers = {["Content-Type"] = content_type}
          })
          assert.response(res).has.status(200)
          local updated_json = assert.response(res).has.jsonbody()
          assert.equal("my-new-upstream", updated_json.name)
          assert.equal(123, updated_json.slots)
          assert.equal(json.id, updated_json.id)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing parameter
            local res = assert(client:send {
              method = "PUT",
              path = "/upstreams",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same({ name = "name is required" }, json)

            -- Invalid parameter
            res = assert(client:send {
              method = "PUT",
              path = "/upstreams",
              body = {
                name = "1.2.3.4", -- ip is not allowed
                created_at = 1461276890000
              },
              headers = {["Content-Type"] = content_type}
            })
            body = assert.response(res).has.status(400)
            local json = cjson.decode(body)
            assert.same({ message = "Invalid name; no ip addresses allowed" }, json)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          return function()
            -- @TODO this particular test actually defeats the purpose of PUT.
            -- It should probably replace the entity
            local res = assert(client:send {
                method = "PUT",
                path = "/upstreams",
                body = {
                  name = "my-upstream",
                  created_at = 1461276890000
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.response(res).has.status(201)
              local json = assert.response(res).has.jsonbody()

              res = assert(client:send {
                method = "PUT",
                path = "/upstreams",
                body = {
                  name = "my-upstream",
                  created_at = json.created_at
                },
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.response(res).has.status(409)
              local json = cjson.decode(body)
              assert.same({ name = "already exists with value 'my-upstream'" }, json)
            end
        end)
      end)
    end)

    describe("GET", function()
      setup(function()
        dao:truncate_tables()

        for i = 1, 10 do
          assert(dao.upstreams:insert {
            name = "upstream-" .. i,
          })
        end
      end)
      teardown(function()
        dao:truncate_tables()
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams"
        })
        assert.response(res).has.status(200)
        local json = assert.response(res).has.jsonbody()
        assert.equal(10, #json.data)
        assert.equal(10, json.total)
      end)
      it("paginates a set", function()
        local pages = {}
        local offset

        for i = 1, 4 do
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams",
            query = {size = 3, offset = offset}
          })
          assert.response(res).has.status(200)
          local json = assert.response(res).has.jsonbody()
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
            path = "/upstreams",
            query = {foo = "bar"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ foo = "unknown field" }, json)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/upstreams",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)

      describe("empty results", function()
        setup(function()
          dao:truncate_tables()
        end)

        it("data property is an empty array", function()
          local res = assert(client:send {
            method = "GET",
            path = "/upstreams"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same({ data = {}, total = 0 }, json)
        end)
      end)
    end)

    describe("DELETE", function()
      it("by id", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.id,
          })

          assert.response(res).has.status(204)
      end)

      it("by name", function(content_type)
          local res = assert(client:send {
            method = "POST",
            path = "/upstreams",
            body = {
              name = "my-upstream",
              slots = 100,
            },
            headers = { ["Content-Type"] = "application/json" }
          })

          assert.response(res).has.status(201)
          local json = assert.response(res).has.jsonbody()

          res = assert(client:send {
            method = "DELETE",
            path = "/upstreams/" .. json.name,
          })

          assert.response(res).has.status(204)
      end)
    end)

    it("returns 405 on invalid method", function()
      local methods = { "DELETE" }

      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/upstreams",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = { ["Content-Type"] = "application/json" }
        })

        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)

  end)
end)

end)
