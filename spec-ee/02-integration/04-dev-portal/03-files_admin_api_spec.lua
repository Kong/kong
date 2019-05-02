local helpers = require "spec.helpers"
local cjson = require "cjson"
local escape = require("socket.url").escape


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


local function configure_portal(db, config)
  config = config or {
    portal = true,
  }

  db.workspaces:upsert_by_name("default", {
    name = "default",
    config = config,
  })
end


for _, strategy in helpers.each_strategy() do

describe("files API (#" .. strategy .. "): ", function()
  local db
  local client
  local fileStub
  local fileSlashStub

  lazy_setup(function()
    _, db, _ = helpers.get_db_utils(strategy)
    assert(helpers.start_kong({
      database = strategy,
      portal = true,
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    db:truncate()
    fileStub = assert(db.files:insert {
      name = "stub",
      contents = "1",
      type = "page"
    })

    fileSlashStub = assert(db.files:insert {
      name = "slash/stub",
      contents = "1",
      type = "page"
    })

    client = helpers.admin_client()
    configure_portal(db)
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
              code = 2,
              fields = {
                contents = "required field missing",
                name = "required field missing",
              },
              message = "2 schema violations (contents: required field missing; name: required field missing)",
              name = "schema violation",
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
            assert.same({
              code = 5,
              fields = {
                name = "stub",
              },
              message = [[UNIQUE violation detected on '{name="stub"}']],
              name = "unique constraint violation",
            }, json)
          end
        end)

        it_content_types("returns 409 on conflicting file (slash in name)", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {
                name = fileSlashStub.name,
                contents = "hello world",
                type = "page"
              },
              headers = {["Content-Type"] = content_type}
            })
            local body = assert.res_status(409, res)
            local json = cjson.decode(body)
            assert.same({
              code = 5,
              fields = {
                name = "slash/stub",
              },
              message = [[UNIQUE violation detected on '{name="slash/stub"}']],
              name = "unique constraint violation",
            }, json)
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
            code = 2,
            fields = {
              contents = "required field missing",
              name = "required field missing",
            },
            message = "2 schema violations (contents: required field missing; name: required field missing)",
            name = "schema violation"
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
            code = 2,
            fields = {
              contents = "required field missing",
              name = "required field missing",
            },
            message = "2 schema violations (contents: required field missing; name: required field missing)",
            name = "schema violation"
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
            code = 2,
            fields = {
              contents = "required field missing",
              name = "required field missing",
            },
            message = "2 schema violations (contents: required field missing; name: required field missing)",
            name = "schema violation",
          }, json)
        end)

        it_content_types("returns 400 on improper type declaration", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {
                name = "test",
                contents = "hello world",
                type = "dog"
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = 2,
              fields = {
                type = "expected one of: page, partial, spec",
              },
              message = "schema violation (type: expected one of: page, partial, spec)",
              name = "schema violation",
            }, json)
          end
        end)

        it_content_types("returns 400 on improper type declaration (slash in name)", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/files",
              body = {
                name = "slash/test",
                contents = "hello world",
                type = "dog"
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
              code = 2,
              fields = {
                type = "expected one of: page, partial, spec",
              },
              message = "schema violation (type: expected one of: page, partial, spec)",
              name = "schema violation",
            }, json)
          end
        end)
      end)
    end)

    describe("GET", function ()
      before_each(function()
        db:truncate('files')

        for i = 1, 100 do
          if math.fmod(i, 2) == 0 then
            assert(db.files:insert {
              name = "file-" .. i,
              contents = "i-" .. i,
              type = "page",
              auth = true
            })
          else
            assert(db.files:insert {
              name = "file-" .. i,
              contents = "i-" .. i,
              type = "partial",
              auth = false
            })
          end
        end
        configure_portal(db)
      end)

      teardown(function()
        db:truncate('files')
      end)

      it("retrieves the first page", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/files"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(100, #json.data)
      end)

      it("paginates correctly", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/files?size=50"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(50, #json.data)

        local next = json.next
        local res = assert(client:send {
          methd = "GET",
          path = next
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(50, #json.data)
        assert.equal(ngx.null, json.next)
      end)

      it("can filter", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/files?type=partial"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(50, #json.data)

        local res = assert(client:send {
          methd = "GET",
          path = "/files?type=page"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(50, #json.data)
      end)

      it("can filter and paginate", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/files?type=partial&size=2"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(2, #json.data)
        assert.equal('partial', json.data[1].type)
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
            path = "/files/" .. escape(fileStub.name),
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

        it("returns 404 if not found (slash in name)", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/stub/something"
          })
          assert.res_status(404, res)
        end)

        it("retrieves by name (slash in name)", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/" .. fileSlashStub.name
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(fileSlashStub, json)
        end)

        it("retrieves by urlencoded name (slash in name)", function()
          local res = assert(client:send {
            method = "GET",
            path = "/files/" .. escape(fileSlashStub.name),
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.same(fileSlashStub, json)
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates by id", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/files/" .. fileStub.id,
              body = {
                contents = "bar",
                name = "changed_name",
                auth = false,
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("bar", json.contents)
            assert.equal("changed_name", json.name)
            assert.equal(false, json.auth)
            assert.equal(fileStub.id, json.id)

            fileStub = assert(db.files:select {
              id = fileStub.id,
            })
            assert.same(json, fileStub)

            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileStub.name
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileStub, json)
          end
        end)

        it_content_types("updates by name", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/files/" .. fileStub.name,
              body = {
                contents = "bar",
                name = "changed_name_again",
                auth = false,
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("bar", json.contents)
            assert.equal("changed_name_again", json.name)
            assert.equal(false, json.auth)
            assert.equal(fileStub.id, json.id)

            fileStub = assert(db.files:select {
              id = fileStub.id,
            })

            assert.same(json, fileStub)

            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileStub.name
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileStub, json)
          end
        end)

        it_content_types("updates by name (slash in name)", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/files/" .. fileSlashStub.name,
              body = {
                contents = "bar",
                name = "changed_name/with_slash",
                auth = true,
              },
              headers = {["Content-Type"] = content_type}
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("bar", json.contents)
            assert.equal("changed_name/with_slash", json.name)
            assert.equal(true, json.auth)
            assert.equal(fileSlashStub.id, json.id)

            fileSlashStub = assert(db.files:select {
              id = fileSlashStub.id,
            })

            assert.same(json, fileSlashStub)


            local res = assert(client:send {
              method = "GET",
              path = "/files/" .. fileSlashStub.name
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(fileSlashStub, json)
          end
        end)
        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/files/_inexistent_",
                body = {
                 name = "alice"
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.res_status(404, res)
            end
          end)

          it_content_types("returns 404 if not found (slash in name)", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/files/stub/_inexistent_",
                body = {
                 name = "alice"
                },
                headers = {["Content-Type"] = content_type}
              })
              assert.res_status(404, res)
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

        it("deletes by name (slash in name)", function()
          local res = assert(client:send {
            method = "DELETE",
            path = "/files/" .. fileSlashStub.name
          })
          local body = assert.res_status(204, res)
          assert.equal("", body)
        end)
      end)
    end)
  end)
end)
end
