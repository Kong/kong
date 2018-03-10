local helpers = require "spec.helpers"
local cjson = require "cjson"
local escape = require("socket.url").escape
local utils = require "kong.tools.utils"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

describe("Admin API", function()
  local client
  setup(function()
    helpers.get_db_utils()
    assert(helpers.start_kong())
  end)
  teardown(function()
    helpers.stop_kong()
  end)

  local consumer, consumer2, consumer3
  before_each(function()
    helpers.dao:truncate_tables()
    consumer = assert(helpers.dao.consumers:insert {
      username = "bob",
      custom_id = "1234"
    })
    consumer2 = assert(helpers.dao.consumers:insert {
      username = "bob pop",  -- containing space for urlencoded test
      custom_id = "abcd"
    })
    consumer3 = assert(helpers.dao.consumers:insert {
      username = "83825bb5-38c7-4160-8c23-54dd2b007f31",  -- uuid format
      custom_id = "1a2b"
    })
    client = helpers.admin_client()
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("/consumers", function()
    describe("POST", function()
      it_content_types("creates a Consumer", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers",
            body = {
              username = "consumer-post"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("consumer-post", json.username)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/consumers",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same(
              {
                custom_id = "At least a 'custom_id' or a 'username' must be specified",
                username  = "At least a 'custom_id' or a 'username' must be specified"
              },
              json
            )
          end
        end)
        it_content_types("returns 409 on conflicting username", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/consumers",
              body = {
                username = "bob"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ username = "already exists with value 'bob'" }, json)
          end
        end)
        it_content_types("returns 409 on conflicting custom_id", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/consumers",
              body = {
                username = "tom",
                custom_id = consumer.custom_id,
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ custom_id = "already exists with value '1234'" }, json)
          end
        end)
        it("returns 415 on invalid content-type", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
            body = '{"hello": "world"}',
            headers = {["Content-Type"] = "invalid"}
          })
          assert.res_status(415, res)
        end)
        it("returns 415 on missing content-type with body ", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
            body = "invalid"
          })
          assert.res_status(415, res)
        end)
        it("returns 400 on missing body with application/json", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)
        it("returns 400 on missing body with multipart/form-data", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
            headers = {["Content-Type"] = "multipart/form-data"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
        it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
            headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
        it("returns 400 on missing body with no content-type header", function()
          local res = assert(client:request {
            method = "POST",
            path = "/consumers",
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
      end)
    end)

    describe("PUT", function()
      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers",
            body = {
              username = "consumer-post"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("consumer-post", json.username)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers",
            body = {
              username = "alice"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
            method = "PUT",
            path = "/consumers",
            body = {
              id = json.id,
              username = "alicia",
              custom_id = "0000",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          body = assert.res_status(200, res)
          local updated_json = cjson.decode(body)
          assert.equal("alicia", updated_json.username)
          assert.equal("0000", updated_json.custom_id)
          assert.equal(json.id, updated_json.id)
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
          path = "/consumers",
          body = {
            id = utils.uuid(),
            username = "alice",
            created_at = 1461276890000,
          },
          headers = { ["Content-Type"] = content_type },
        })
        assert.res_status(404, res)
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PUT",
              path = "/consumers",
              body = {},
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same(
              {
                custom_id = "At least a 'custom_id' or a 'username' must be specified",
                username  = "At least a 'custom_id' or a 'username' must be specified"
              },
              json
            )
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
          -- @TODO this particular test actually defeats the purpose of PUT.
          -- It should probably replace the entity
          return function()
            local res = assert(client:send {
              method = "PUT",
              path = "/consumers",
              body = {
                username = "alice"
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.res_status(201, res)

            res = assert(client:send {
              method = "PUT",
              path = "/consumers",
              body = {
                username = "alice",
                custom_id = "0000"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ username = "already exists with value 'alice'" }, json)
          end
        end)
        it("returns 415 on invalid content-type", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
            body = '{"hello": "world"}',
            headers = {["Content-Type"] = "invalid"}
          })
          assert.res_status(415, res)
        end)
        it("returns 415 on missing content-type with body ", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
            body = "invalid"
          })
          assert.res_status(415, res)
        end)
        it("returns 400 on missing body with application/json", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)
        it("returns 400 on missing body with multipart/form-data", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
            headers = {["Content-Type"] = "multipart/form-data"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
        it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
            headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
        it("returns 400 on missing body with no content-type header", function()
          local res = assert(client:request {
            method = "PUT",
            path = "/consumers",
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            custom_id = "At least a 'custom_id' or a 'username' must be specified",
            username  = "At least a 'custom_id' or a 'username' must be specified",
          }, json)
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        helpers.dao:truncate_tables()

        for i = 1, 10 do
          assert(helpers.dao.consumers:insert {
            username = "consumer-" .. i,
          })
        end
      end)
      teardown(function()
        helpers.dao:truncate_tables()
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/consumers"
        })
        res = assert.res_status(200, res)
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
            path = "/consumers",
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
          path = "/consumers",
          query = {foo = "bar"}
        })
        local body = assert.res_status(400, res)
        local json = cjson.decode(body)
        assert.same({ foo = "unknown field" }, json)
      end)
    end)
    it("returns 405 on invalid method", function()
      local methods = {"DELETE", "PATCH"}
      for i = 1, #methods do
        local res = assert(client:send {
          method = methods[i],
          path = "/consumers",
          body = {}, -- tmp: body to allow POST/PUT to work
          headers = {["Content-Type"] = "application/json"}
        })
        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)
        assert.same({ message = "Method not allowed" }, json)
      end
    end)

    describe("/consumers/{consumer}", function()
      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. consumer.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer, json)
        end)
        it("retrieves by username", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. consumer.username
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer, json)
        end)
        it("retrieves by username in uuid format", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. consumer3.username
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer3, json)
        end)
        it("retrieves by urlencoded username", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/" .. escape(consumer2.username)
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer2, json)
        end)
        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/_inexistent_"
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates by id", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              body = {
                username = "alice"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(consumer.id, json.id)

            local in_db = assert(helpers.dao.consumers:find {id = consumer.id})
            assert.same(json, in_db)
          end
        end)
        it_content_types("updates by username", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/consumers/" .. consumer.username,
              body = {
                username = "alice"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("alice", json.username)
            assert.equal(consumer.id, json.id)

            local in_db = assert(helpers.dao.consumers:find {id = consumer.id})
            assert.same(json, in_db)
          end
        end)
        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/consumers/_inexistent_",
                body = {
                 username = "alice"
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
                path = "/consumers/" .. consumer.id,
                body = {},
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({ message = "empty body" }, json)
            end
          end)
          it("returns 415 on invalid content-type", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              body = '{"hello": "world"}',
              headers = {["Content-Type"] = "invalid"}
            })
            assert.res_status(415, res)
          end)
          it("returns 415 on missing content-type with body ", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              body = "invalid"
            })
            assert.res_status(415, res)
          end)
          it("returns 400 on missing body with application/json", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot parse JSON body" }, json)
          end)
          it("returns 400 on missing body with multipart/form-data", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              headers = {["Content-Type"] = "multipart/form-data"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "empty body" }, json)
          end)
          it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
              headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "empty body" }, json)
          end)
          it("returns 400 on missing body with no content-type header", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/consumers/" .. consumer.id,
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "empty body" }, json)
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes by id", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/consumers/" .. consumer.id
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        it("deletes by username", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/consumers/" .. consumer.username
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        describe("error", function()
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/consumers/_inexistent_"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)

  describe("/consumers/{username_or_id}/plugins", function()
    before_each(function()
      helpers.dao.plugins:truncate()
    end)
    describe("POST", function()
      it_content_types("creates a plugin config using a consumer id", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              name = "rewriter",
              ["config.value"] = "potato",
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.same("potato", json.config.value)
        end
      end)
      it_content_types("creates a plugin config using a consumer username with a space on it", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers/" .. consumer2.username .. "/plugins",
            body = {
              name = "rewriter",
              ["config.value"] = "potato",
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.same("potato", json.config.value)
        end
      end)
      it_content_types("creates a plugin config using a consumer username in uuid format", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/consumers/" .. consumer3.username .. "/plugins",
            body = {
              name = "rewriter",
              ["config.value"] = "potato",
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.same("potato", json.config.value)
        end
      end)
      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/consumers/" .. consumer.id .. "/plugins",
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
              path = "/consumers/" .. consumer.id .. "/plugins",
              body = {
                name="rewriter",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(201)
            assert.response(res).has.jsonbody()

            -- do it again, to provoke the error
            local res = assert(client:send {
              method = "POST",
              path = "/consumers/" .. consumer.id .. "/plugins",
              body = {
                name="rewriter",
              },
              headers = {["Content-Type"] = content_type}
            })
            assert.response(res).has.status(409)
            local json = assert.response(res).has.jsonbody()
            assert.same({ name = "already exists with value 'rewriter'"}, json)
          end
        end)
      end)
    end)

    describe("PUT", function()
      it_content_types("creates if not exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              name = "rewriter",
              ["config.value"] = "potato",
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.equal("potato", json.config.value)
        end
      end)
      it_content_types("replaces if exists", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              name = "rewriter",
              ["config.value"] = "potato",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              id = json.id,
              name = "rewriter",
              ["config.value"] = "carrot",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          body = assert.res_status(200, res)
          json = cjson.decode(body)
          assert.equal("rewriter", json.name)
          assert.equal("carrot", json.config.value)
        end
      end)
      it_content_types("prefers default values when replacing", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "rewriter",
            consumer_id = consumer.id,
            config = { value = "potato", extra = "super" }
          })
          assert.equal("potato", plugin.config.value)
          assert.equal("super", plugin.config.extra)

          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              id = plugin.id,
              name = "rewriter",
              ["config.value"] = "carrot",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(json.config.value, "carrot")
          assert.equal(json.config.extra, "extra") -- changed to the default value

          plugin = assert(helpers.dao.plugins:find {
            id = plugin.id,
            name = plugin.name
          })
          assert.equal(plugin.config.value, "carrot")
          assert.equal(plugin.config.extra, "extra") -- changed to the default value
        end
      end)
      it_content_types("overrides a plugin previous config if partial", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "rewriter",
            consumer_id = consumer.id
          })
          assert.equal("extra", plugin.config.extra)

          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              id = plugin.id,
              name = "rewriter",
              ["config.extra"] = "super",
              created_at = 1461276890000
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same("super", json.config.extra)
        end
      end)
      it_content_types("updates the enabled property", function(content_type)
        return function()
          local plugin = assert(helpers.dao.plugins:insert {
            name = "rewriter",
            consumer_id = consumer.id
          })
          assert.True(plugin.enabled)

          local res = assert(client:send {
            method = "PUT",
            path = "/consumers/" .. consumer.id .. "/plugins",
            body = {
              id = plugin.id,
              name = "rewriter",
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
              path = "/consumers/" .. consumer.id .. "/plugins",
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
      it("retrieves the first page", function()
        assert(helpers.dao.plugins:insert {
          name = "rewriter",
          consumer_id = consumer.id
        })
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. consumer.id .. "/plugins"
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.equal(1, #json.data)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. consumer.id .. "/plugins",
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

  end)


  describe("/consumers/{username_or_id}/plugins/{plugin}", function()
    local plugin, plugin2
    before_each(function()
      plugin = assert(helpers.dao.plugins:insert {
        name = "rewriter",
        consumer_id = consumer.id
      })
      plugin2 = assert(helpers.dao.plugins:insert {
        name = "rewriter",
        consumer_id = consumer2.id
      })
    end)

    describe("GET", function()
      it("retrieves by id", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(plugin, json)
      end)
      it("retrieves by consumer id when it has spaces", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. consumer2.id .. "/plugins/" .. plugin2.id
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(plugin2, json)
      end)
      it("only retrieves if associated to the correct consumer", function()
        -- Create an consumer and try to query our plugin through it
        local w_consumer = assert(helpers.dao.consumers:insert {
          custom_id = "wc",
          username = "wrong-consumer"
        })

        -- Try to request the plugin through it (belongs to the fixture consumer instead)
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. w_consumer.id .. "/plugins/" .. plugin.id
        })
        assert.res_status(404, res)
      end)
      it("ignores an invalid body", function()
        local res = assert(client:send {
          method = "GET",
          path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id,
          body = "this fails if decoded as json",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })
        assert.res_status(200, res)
      end)
    end)

    describe("PATCH", function()
      it_content_types("updates if found", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id,
            body = {
              ["config.value"] = "updated"
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("updated", json.config.value)
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
          plugin = assert(helpers.dao.plugins:update(
              { config = { value = "potato" } },
              { id = plugin.id, name = plugin.name }
          ))
          assert.equal("potato", plugin.config.value)
          assert.equal("extra", plugin.config.extra )

          local res = assert(client:send {
            method = "PATCH",
            path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id,
            body = {
              ["config.value"] = "carrot",
            },
            headers = {["Content-Type"] = content_type}
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal("carrot", json.config.value)
          assert.equal("extra", json.config.extra)

          plugin = assert(helpers.dao.plugins:find {
            id = plugin.id,
            name = plugin.name
          })
          assert.equal("carrot", plugin.config.value)
          assert.equal("extra", plugin.config.extra)
        end
      end)
      it_content_types("updates the enabled property", function(content_type)
        return function()
          local res = assert(client:send {
            method = "PATCH",
            path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id,
            body = {
              name = "rewriter",
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
              path = "/consumers/" .. consumer.id .. "/plugins/b6cca0aa-4537-11e5-af97-23a06d98af51",
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
              path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id,
              body = {
                name = "foo"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ config = "plugin 'foo' not enabled; add it to the 'custom_plugins' configuration property" }, json)
          end
        end)
      end)
    end)

    describe("DELETE", function()
      it("deletes a plugin configuration", function()
        local res = assert(client:send {
          method = "DELETE",
          path = "/consumers/" .. consumer.id .. "/plugins/" .. plugin.id
        })
        assert.res_status(204, res)
      end)
      describe("errors", function()
        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/consumers/" .. consumer.id .. "/plugins/fafafafa-1234-baba-5678-cececececece"
          })
          assert.res_status(404, res)
        end)
      end)
    end)
  end)
end)
