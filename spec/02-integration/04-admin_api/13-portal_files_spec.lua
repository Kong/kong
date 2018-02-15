local helpers = require "spec.helpers"
local escape = require("socket.url").escape
local cjson = require "cjson"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end

describe("Admin API - Developer Portal Files", function()
  local client

  setup(function()
    helpers.run_migrations()
    assert(helpers.start_kong())
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  local fileStub
  before_each(function()
    helpers.dao:truncate_tables()
    fileStub = assert(helpers.dao.portal_files:insert {
      name = "stub",
      contents = "1",
      type = "page"
    })
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then client:close() end
  end)

  describe("/files", function()
    describe("POST", function()
      it_content_types("creates a page", function(content_type)
        return function()
          local res = assert(client:send {
            method = "POST",
            path = "/files",
            body = {
              name = "test",
              contents = "hello world",
              type = "page"
            },
            headers = {["Content-Type"] = content_type}
          })

          local body = assert.res_status(201, res)
          local json = cjson.decode(body)

          assert.equal("test", json.name)
          assert.equal("hello world", json.contents)
          assert.equal("page", json.type)
          assert.is_true(json.auth)
          assert.is_number(json.created_at)
          assert.is_string(json.id)
        end
      end)

      describe("errors", function()
        it_content_types("handles invalid input", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {},
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(400, res)
            local json = cjson.decode(body)

            assert.same({
              name = "name is required",
              contents  = "contents is required",
              type = "type is required"
            }, json)
          end
        end)

        it_content_types("returns 409 on conflicting file", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {
                name = fileStub.name,
                contents = "hello world",
                type = "page"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({ name = "already exists with value '" .. fileStub.name .. "'" }, json)
          end
        end)

        it("returns 415 on invalid content-type", function()
          local res = assert(client:send {
            method = "POST",
            path = "/files",
            body = '{}',
            headers = {["Content-Type"] = "invalid"}
          })
          assert.res_status(415, res)
        end)

        it("returns 415 on missing content-type with body", function()
          local res = assert(client:request {
            method = "POST",
            path = "/files",
            body = "invalid"
          })
          assert.res_status(415, res)
        end)

        it("returns 400 on missing body with application/json", function()
          local res = assert(client:request {
            method = "POST",
            path = "/files",
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({ message = "Cannot parse JSON body" }, json)
        end)

        it("returns 400 on missing body with multipart/form-data", function()
          local res = assert(client:request {
            method = "POST",
            path = "/files",
            headers = {["Content-Type"] = "multipart/form-data"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            name  = "name is required",
            contents = "contents is required",
            type = "type is required"
          }, json)
        end)

        it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
          local res = assert(client:request {
            method = "POST",
            path = "/files",
            headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            name  = "name is required",
            contents = "contents is required",
            type = "type is required"
          }, json)
        end)

        it("returns 400 on missing body with no content-type header", function()
          local res = assert(client:request {
            method = "POST",
            path = "/files",
          })
          local body = assert.res_status(400, res)
          local json = cjson.decode(body)
          assert.same({
            name  = "name is required",
            contents = "contents is required",
            type = "type is required"
          }, json)
        end)
      end)
    end)

    describe("GET", function ()
      before_each(function()
        helpers.dao:truncate_tables()

        for i = 1, 10 do
          assert(helpers.dao.portal_files:insert {
            name = "file-" .. i,
            contents = "i-" .. i,
            type = "partial"
          })
        end
      end)

      teardown(function()
        helpers.dao:truncate_tables()
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/files"
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
            path = "/files",
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
          path = "/files",
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
          path = "/files",
          body = {},
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.response(res).has.status(405)
        local json = cjson.decode(body)

        assert.same({ message = "Method not allowed" }, json)
      end
    end)

    describe("/files/{file_splat}", function()
      describe("GET", function()
        it("retrieves by id", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/" .. fileStub.id
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(fileStub, json)
        end)

        it("retrieves by name", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/" .. fileStub.name
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(fileStub, json)
        end)

        it("retrieves by urlencoded name", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/" .. escape(fileStub.name)
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(fileStub, json)
        end)

        it("returns 404 if not found", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/_inexistent_"
          })
          assert.res_status(404, res)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates by id", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              body = {
                contents = "bar"
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("bar", json.contents)
            assert.equal(fileStub.id, json.id)

            local in_db = assert(helpers.dao.portal_files:find {id = fileStub.id})
            assert.same(json, in_db)
          end
        end)

        it_content_types("updates by name", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/files/" .. fileStub.name,
              body = {
                contents = "bar"
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("bar", json.contents)
            assert.equal(fileStub.id, json.id)

            local in_db = assert(helpers.dao.portal_files:find {id = fileStub.id})
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
                path = "/files/" .. fileStub.id,
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
              path = "/files/" .. fileStub.id,
              body = '{"hello": "world"}',
              headers = {["Content-Type"] = "invalid"}
            })
            assert.res_status(415, res)
          end)
          it("returns 415 on missing content-type with body ", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              body = "invalid"
            })
            assert.res_status(415, res)
          end)
          it("returns 400 on missing body with application/json", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "Cannot parse JSON body" }, json)
          end)
          it("returns 400 on missing body with multipart/form-data", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              headers = {["Content-Type"] = "multipart/form-data"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "empty body" }, json)
          end)
          it("returns 400 on missing body with multipart/x-www-form-urlencoded", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              headers = {["Content-Type"] = "application/x-www-form-urlencoded"}
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({ message = "empty body" }, json)
          end)
          it("returns 400 on missing body with no content-type header", function()
            local res = assert(client:request {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
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
            path = "/files/" .. fileStub.id
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        it("deletes by name", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/files/" .. fileStub.name
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
        describe("error", function()
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/files/_inexistent_"
            })
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end)
