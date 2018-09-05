local helpers    = require "spec.helpers"
local ee_helpers = require "spec.ee_helpers"
local escape     = require("socket.url").escape
local cjson      = require "cjson"
local enums      = require "kong.enterprise_edition.dao.enums"

local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with application/json", test_json)
end


for _, strategy in helpers.each_strategy() do
describe("Admin API - Developer Portal - " .. strategy, function()
  local client
  local portal_client
  local db
  local dao

  setup(function()
    _, db, dao = helpers.get_db_utils(strategy)

    assert(helpers.start_kong({
      portal = true,
      database = strategy,
    }))
  end)

  teardown(function()
    helpers.stop_kong()
  end)

  local fileStub
  before_each(function()
    dao:truncate_tables()

    fileStub = assert(dao.portal_files:insert {
      name = "stub",
      contents = "1",
      type = "page"
    })
    client = assert(helpers.admin_client())
  end)

  after_each(function()
    if client then client:close() end
    if portal_client then portal_client:close() end
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
        dao:truncate_tables()

        for i = 1, 10 do
          assert(dao.portal_files:insert {
            name = "file-" .. i,
            contents = "i-" .. i,
            type = "partial"
          })
        end
      end)

      teardown(function()
        dao:truncate_tables()
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

            local in_db = assert(dao.portal_files:find {
              id = fileStub.id,
              name = fileStub.name,
            })
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

            local in_db = assert(dao.portal_files:find {
              id = fileStub.id,
              name = fileStub.name,
            })
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

  describe("/portal/developers", function()
    describe("GET", function ()

      before_each(function()
        local portal = require "kong.portal.dao_helpers"
        dao:truncate_tables()

        portal.register_resources(dao)

        for i = 1, 10 do
          assert(dao.consumers:insert {
            username = "proxy-consumer-" .. i,
            custom_id = "proxy-consumer-" .. i,
            type = enums.CONSUMERS.TYPE.PROXY,
          })
          -- only insert half as many developers
          if i % 2 == 0 then
            assert(dao.consumers:insert {
              username = "developer-consumer-" .. i,
              custom_id = "developer-consumer-" .. i,
              type = enums.CONSUMERS.TYPE.DEVELOPER
            })
          end
        end
      end)

      teardown(function()
        dao:truncate_tables()
      end)

      it("retrieves list of developers only", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/portal/developers"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)
      end)

      it("cannot retrieve proxy consumers", function()
        local res = assert(client:send {
          methd = "GET",
          path = "/portal/developers?type=0"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(5, #json.data)
      end)

      it("filters by developer status", function()
        assert(dao.consumers:insert {
          username = "developer-pending",
          custom_id = "developer-pending",
          type = enums.CONSUMERS.TYPE.DEVELOPER,
          status = enums.CONSUMERS.STATUS.PENDING
        })

        local res = assert(client:send {
          methd = "GET",
          path = "/portal/developers/?status=1"
        })
        res = assert.res_status(200, res)
        local json = cjson.decode(res)
        assert.equal(1, #json.data)
      end)
    end)
  end)

  describe("/portal/developers/:email_or_id", function()
    local developer
    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      helpers.register_consumer_relations(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "off",
      }))

      portal_client = assert(ee_helpers.portal_client())
      client = assert(helpers.admin_client())

      local res = assert(portal_client:send {
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      local body = assert.res_status(201, res)
      local resp_body_json = cjson.decode(body)
      developer = resp_body_json.consumer
    end)

    describe("PATCH", function()
      describe("smtp = on", function()
        it("sends an email to the approved developer", function()
          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = 0
            },
            path = "/portal/developers/".. developer.id,
            headers = {["Content-Type"] = "application/json"}
          })

          local expected_email = {
            error = {
              count = 0,
              emails = {},
            },
            sent = {
              count = 1,
              emails = {
                ["gruce@konghq.com"] = true,
              }
            },
            smtp_mock = true,
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          assert.same(expected_email, resp_body_json.email)
        end)

        it("does not send an email if the developer is not approved", function()
          local res = assert(client:send {
            method = "PATCH",
            body = {
              status = 2
            },
            path = "/portal/developers/".. developer.id,
            headers = {["Content-Type"] = "application/json"}
          })

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)
          assert.is_nil(resp_body_json.email)
        end)
      end)
    end)
  end)

  describe("/portal/developers/:email_or_id/password", function()
    local developer
    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      helpers.register_consumer_relations(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "on",
      }))

      portal_client = assert(ee_helpers.portal_client())
      client = assert(helpers.admin_client())

      local res = assert(portal_client:send {
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      local body = assert.res_status(201, res)
      local resp_body_json = cjson.decode(body)
      developer = resp_body_json.consumer
    end)

    describe("PATCH", function()
      it("returns 400 if patched with no password", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {},
          path = "/portal/developers/".. developer.id .."/password",
          headers = {["Content-Type"] = "application/json"}
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)
        local message = resp_body_json.message

        assert.equal("Password is required", message)
      end)

      it("updates the password", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            password = "hunter1"
          },
          path = "/portal/developers/".. developer.id .."/password",
          headers = {["Content-Type"] = "application/json"}
        })

        assert.res_status(204, res)

        -- old password fails
        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        assert.res_status(403, res)

        -- new password auths
        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:hunter1"),
          }
        })

        assert.res_status(200, res)
      end)
    end)
  end)

  describe("/portal/developers/:email_or_id/email", function()
    local developer
    local developer2

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      helpers.register_consumer_relations(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "on",
      }))

      portal_client = assert(ee_helpers.portal_client())
      client = assert(helpers.admin_client())

      local res = assert(portal_client:send {
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      local body = assert.res_status(201, res)
      local resp_body_json = cjson.decode(body)
      developer = resp_body_json.consumer

      local res = assert(portal_client:send {
        method = "POST",
        path = "/register",
        body = {
          email = "fancypants@konghq.com",
          password = "mowmow",
          meta = "{\"full_name\":\"Old Gregg\"}"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      local body = assert.res_status(201, res)
      local resp_body_json = cjson.decode(body)
      developer2 = resp_body_json.consumer
    end)

    describe("PATCH", function()
      it("returns 400 if patched with an invalid email", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = "emailol.com",
          },
          path = "/portal/developers/".. developer.id .."/email",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(400, res)
        local resp_body_json = cjson.decode(body)
        local message = resp_body_json.message

        assert.equal("Invalid email: missing '@' symbol", message)
      end)

      it("returns 409 if patched with an email that already exists", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = developer2.email,
          },
          path = "/portal/developers/".. developer.id .."/email",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        local body = assert.res_status(409, res)
        local resp_body_json = cjson.decode(body)
        local message = resp_body_json.username

        assert.equal("already exists with value 'fancypants@konghq.com'", message)
      end)

      it("updates both email and username from passed email", function()
        local res = assert(client:send {
          method = "PATCH",
          body = {
            email = "new_email@whodis.com",
          },
          path = "/portal/developers/".. developer.id .."/email",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(204, res)

        -- old email fails
        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        assert.res_status(403, res)

        -- new email succeeds
        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("new_email@whodis.com:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        assert.equal("new_email@whodis.com", resp_body_json.email)
        assert.equal("new_email@whodis.com", resp_body_json.username)
      end)
    end)
  end)

  describe("/portal/developers/:email_or_id/meta", function()
    local developer

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      helpers.register_consumer_relations(dao)

      assert(helpers.start_kong({
        database   = strategy,
        portal     = true,
        portal_auth = "basic-auth",
        portal_auth_config = "{ \"hide_credentials\": true }",
        portal_auto_approve = "on",
      }))

      portal_client = assert(ee_helpers.portal_client())
      client = assert(helpers.admin_client())

      local res = assert(portal_client:send {
        method = "POST",
        path = "/register",
        body = {
          email = "gruce@konghq.com",
          password = "kong",
          meta = "{\"full_name\":\"I Like Turtles\"}"
        },
        headers = {["Content-Type"] = "application/json"}
      })

      local body = assert.res_status(201, res)
      local resp_body_json = cjson.decode(body)
      developer = resp_body_json.consumer
    end)

    describe("PATCH", function()
      it("updates the meta", function()
        local new_meta = "{\"full_name\":\"KONG!!!\"}"

        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = new_meta
          },
          path = "/portal/developers/".. developer.id .."/meta",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(204, res)

        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local meta = resp_body_json.meta

        assert.equal(meta, new_meta)
      end)

      it("ignores keys that are not in the current meta", function()
        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local current_meta = resp_body_json.meta

        local new_meta = "{\"new_key\":\"not in current meta\"}"

        local res = assert(client:send {
          method = "PATCH",
          body = {
            meta = new_meta
          },
          path = "/portal/developers/".. developer.id .."/meta",
          headers = {
            ["Content-Type"] = "application/json",
          }
        })

        assert.res_status(204, res)

        local res = assert(portal_client:send {
          method = "GET",
          path = "/developer",
          headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Basic " .. ngx.encode_base64("gruce@konghq.com:kong"),
          }
        })

        local body = assert.res_status(200, res)
        local resp_body_json = cjson.decode(body)
        local new_meta = resp_body_json.meta

        assert.equal(new_meta, current_meta)
      end)
    end)
  end)

  describe("/portal/invite", function()
    describe("POST", function()
      describe("portal_invite_email = off", function()
        before_each(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_invite_email = "off",
          }))

          client = assert(helpers.admin_client())
        end)

        it("returns 501 if portal_invite_email is turned off", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com"},
            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(501, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("portal_invite_email is disabled", message)
        end)
      end)

      describe("smtp = on, valid config", function()
        before_each(function()
          helpers.stop_kong()
          assert(db:truncate())
          helpers.register_consumer_relations(dao)

          assert(helpers.start_kong({
            database   = strategy,
            portal     = true,
            portal_auth = "basic-auth",
            portal_auth_config = "{ \"hide_credentials\": true }",
            portal_auto_approve = "off",
            portal_emails_from = "me@example.com",
            portal_emails_reply_to = "me@example.com",
            smtp = "on",
            smtp_mock = "on",
          }))

          client = assert(helpers.admin_client())
        end)

        it("returns 400 if not sent with emails param", function()
          local res = assert(client:send {
            method = "POST",
            body = {

            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("emails param required", message)
        end)

        it("returns 400 if emails is empty", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {},
            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)
          local message = resp_body_json.message

          assert.equal("emails param required", message)
        end)

        it("returns 200 if emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com", "you@example.com"},
            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 0,
              emails = {},
            },
            sent = {
              count = 2,
              emails = {
                ["me@example.com"] = true,
                ["you@example.com"] = true,
              },
            }
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json)
        end)

        it("returns 200 if some of the emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"me@example.com", "bademail.com"},
            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 1,
              emails = {
                ["bademail.com"] = "Invalid email: missing '@' symbol",
              },
            },
            sent = {
              count = 1,
              emails = {
                ["me@example.com"] = true,
              },
            }
          }

          local body = assert.res_status(200, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json)
        end)

        it("returns 400 if none of the emails are sent", function()
          local res = assert(client:send {
            method = "POST",
            body = {
              emails = {"notemail", "bademail.com"},
            },
            path = "/portal/invite",
            headers = {
              ["Content-Type"] = "application/json",
            }
          })

          local expected = {
            smtp_mock = true,
            error = {
              count = 2,
              emails = {
                ["notemail"] = "Invalid email: missing '@' symbol",
                ["bademail.com"] = "Invalid email: missing '@' symbol",
              },
            },
            sent = {
              count = 0,
              emails = {},
            }
          }

          local body = assert.res_status(400, res)
          local resp_body_json = cjson.decode(body)

          assert.same(expected, resp_body_json.message)
        end)
      end)
    end)
  end)
end)
end
