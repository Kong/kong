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
    helpers.kill_all()
    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.test_conf.admin_port))
  end)
  teardown(function()
    if client then client:close() end
    helpers.stop_kong()
    --helpers.clean_prefix()
  end)

  local consumer
  before_each(function()
    helpers.dao:truncate_tables()
    consumer = assert(helpers.dao.consumers:insert {
      username = "bob",
      custom_id = "1234"
    })
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
            assert.equal([[{"custom_id":"At least a 'custom_id' or a 'username' ]]
                       ..[[must be specified","username":"At least a 'custom_id' or ]]
                       ..[[a 'username' must be specified"}]], body)
          end
        end)
        it_content_types("returns 409 on conflict", function(content_type)
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
            assert.equal([[{"username":"already exists with value 'bob'"}]], body)
          end
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
            assert.equal([[{"custom_id":"At least a 'custom_id' or a 'username' ]]
                       ..[[must be specified","username":"At least a 'custom_id' or ]]
                       ..[[a 'username' must be specified"}]], body)
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
            assert.equal([[{"username":"already exists with value 'alice'"}]], body)
          end
        end)
      end)
    end)

    describe("GET", function()
      before_each(function()
        helpers.dao:truncate_tables()

        for i = 1, 10 do
          assert(helpers.dao.consumers:insert {
            username = "consumer-"..i,
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
        assert.equal([[{"foo":"unknown field"}]], body)
      end)
    end)

    describe("/consumers/{consumer}", function()
      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/"..consumer.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer, json)
        end)
        it("retrieves by username", function()
          local res = assert(client:send {
            method = "GET",
            path = "/consumers/"..consumer.username
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(consumer, json)
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
              path = "/consumers/"..consumer.id,
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
              path = "/consumers/"..consumer.username,
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
                path = "/consumers/"..consumer.id,
                body = {},
                headers = {["Content-Type"] = content_type}
              })
              local body = assert.res_status(400, res)
              assert.equal([[{"message":"empty body"}]], body)
            end
          end)
        end)
      end)

      describe("DELETE", function()
        it("deletes by id", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/consumers/"..consumer.id
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        it("deletes by username", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/consumers/"..consumer.username
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
end)
