local cjson   = require "cjson"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"


local unindent = helpers.unindent


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/json", test_json)
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy, function()
    local db
    local client

    setup(function()
      local _
      _, db = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
      }))

      client = assert(helpers.admin_client())
    end)

    teardown(function()
      if client then
        client:close()
      end

      helpers.stop_kong()
    end)

    before_each(function()
      assert(db:truncate())
    end)

    describe("/services", function()
      describe("POST", function()
        it_content_types("creates a service", function(content_type)
          return function()
            local res = client:post("/services", {
              body = {
                protocol = "http",
                host     = "service.com",
              },
              headers = { ["Content-Type"] = content_type },
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            assert.is_string(json.id)
            assert.is_number(json.created_at)
            assert.is_number(json.updated_at)
            assert.equals(cjson.null, json.name)
            assert.equals("http", json.protocol)
            assert.equals("service.com", json.host)
            assert.equals(80, json.port)
            assert.equals(60000, json.connect_timeout)
            assert.equals(60000, json.write_timeout)
            assert.equals(60000, json.read_timeout)
          end
        end)

        it_content_types("creates a service with url ", function(content_type)
          return function()
            local res = client:post("/services", {
              body = {
                url = "http://service.com/",
              },
              headers = { ["Content-Type"] = content_type },
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            assert.is_string(json.id)
            assert.is_number(json.created_at)
            assert.is_number(json.updated_at)
            assert.equals(cjson.null, json.name)
            assert.equals("http", json.protocol)
            assert.equals("service.com", json.host)
            assert.equals("/", json.path)
            assert.equals(80, json.port)
            assert.equals(60000, json.connect_timeout)
            assert.equals(60000, json.write_timeout)
            assert.equals(60000, json.read_timeout)
          end
        end)
      end)

      describe("/services/:id/routes", function()
        it_content_types("lists all routes belonging to service", function(content_type)
          return function()
            local service = db.services:insert({
              protocol = "http",
              host     = "service.com",
            })

            local route = db.routes:insert({
              protocol = "http",
              hosts    = { "service.com" },
              service  = service,
            })

            local _ = db.routes:insert({
              protocol = "http",
              hosts    = { "service.com" },
            })

            local res = client:get("/services/" .. service.id .. "/routes", {
              headers = { ["Content-Type"] = content_type },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.same({ data = { route }, next = cjson.null }, json)
          end
        end)
      end)

      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = client:post("/services", {
              body    = '{"hello": "world"',
              headers = { ["Content-Type"] = "application/json" }
            })
          local body = assert.res_status(400, res)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)

        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing params
            local res = client:post("/services", {
                body = {},
                headers = { ["Content-Type"] = content_type }
              })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
                host = "required field missing",
              }, json.fields)

            -- Invalid parameter
            res = client:post("/services", {
                body = {
                  host     = "example.com",
                  protocol = "foo",
                },
                headers = { ["Content-Type"] = content_type }
              })
            body = assert.res_status(400, res)
            json = cjson.decode(body)
            assert.same({ protocol = "expected one of: http, https" }, json.fields)
          end
        end)

        it_content_types("handles invalid url ", function(content_type)
          return function()
            local res = client:post("/services", {
              body = {
                url = "invalid url",
              },
              headers = { ["Content-Type"] = content_type },
            })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same(
              {
                name    = "schema violation",
                code    = Errors.codes.SCHEMA_VIOLATION,
                message = unindent([[
                  2 schema violations
                  (host: required field missing;
                  path: should start with: /)
                ]], true, true),
                fields = {
                  host = "required field missing",
                  path = "should start with: /",
                },
              }, json
            )
          end
        end)
      end)

      describe("GET", function()
        describe("with data", function()
          before_each(function()
            for i = 1, 10 do
              assert(db.services:insert {
                host = ("example%d.com"):format(i)
              })
            end
          end)

          it("retrieves the first page", function()
            local res = client:get("/services")
            local res = assert.res_status(200, res)
            local json = cjson.decode(res)
            assert.equal(10, #json.data)
          end)

          it("paginates a set", function()
            local pages = {}
            local offset

            for i = 1, 4 do
              local res = client:get("/services",
                                     { query  = { size = 3, offset = offset }})
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)

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
        end)

        describe("with no data", function()
          it("data property is an empty array and not an empty hash", function()
            local res = client:get("/services")
            local body = assert.res_status(200, res)
            assert.matches('"data":%[%]', body)
            local json = cjson.decode(body)
            assert.same({ data = {}, next = cjson.null }, json)
          end)
        end)

        describe("errors", function()
          it("handles invalid filters", function()
            local res  = client:get("/services", { query = { foo = "bar" } })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({ data = {}, next = cjson.null }, json)
          end)

          it("ignores an invalid body", function()
            local res = client:get("/routes", {
              body = "this fails if decoded as json",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(200, res)
          end)
        end)
      end)

--      it("returns HTTP 405 on invalid method", function()
--        local methods = { "DELETE" }
--
--        for i = 1, #methods do
--          local res = assert(client:send {
--            method = methods[i],
--            path = "/services",
--            body = {}, -- tmp: body to allow POST/PUT to work
--            headers = {
--              ["Content-Type"] = "application/json"
--            }
--          })
--          local body = assert.response(res).has.status(405)
--          local json = cjson.decode(body)
--          assert.same({ message = "Method not allowed" }, json)
--        end
--      end)
--
--      describe("/services/{route}", function()
--        local route
--
--        before_each(function()
--          route = assert(db.services:insert {
--            protocol = "http",
--            paths    = { "/my-route" },
--          })
--        end)
--
--        describe("GET", function()
--          it("retrieves by id", function()
--            local res  = client:get("/services/" .. route.id)
--            local body = assert.res_status(200, res)
--            local json = cjson.decode(body)
--            assert.same(route, json)
--          end)
--
--          it("returns 404 if not found", function()
--            local res = client:get("/services/" .. utils.uuid())
--            assert.res_status(404, res)
--          end)
--
--          it("ignores an invalid body", function()
--            local res = client:get("/services/" .. route.id, {
--              headers = {
--                ["Content-Type"] = "application/json"
--              },
--              body = "this fails if decoded as json",
--            })
--            assert.res_status(200, res)
--          end)
--        end)
--
--        describe("PATCH", function()
--          it_content_types("updates if found", function(content_type)
--            return function()
--              local res = client:patch("/services/" .. route.id, {
--                headers = {
--                  ["Content-Type"] = content_type
--                },
--                body = {
--                  methods = cjson.null,
--                  hosts   = cjson.null,
--                  paths   = { "/updated-paths" },
--                },
--              })
--              local body = assert.res_status(200, res)
--              local json = cjson.decode(body)
--              assert.same({ "/updated-paths" }, json.paths)
--              assert.same(cjson.null, json.hosts)
--              assert.same(cjson.null, json.methods)
--              assert.equal(route.id, json.id)
--
--              local in_db = assert(db.services:select({ id = route.id }))
--              assert.same(json, in_db)
--            end
--          end)
--
--          it_content_types("updates strip_path if not previously set", function(content_type)
--            return function()
--              local res = client:patch("/services/" .. route.id, {
--                headers = {
--                  ["Content-Type"] = content_type
--                },
--                body = {
--                  strip_path = true
--                },
--              })
--              local body = assert.res_status(200, res)
--              local json = cjson.decode(body)
--              assert.True(json.strip_path)
--              assert.equal(route.id, json.id)
--
--              local in_db = assert(db.services:select({id = route.id}))
--              assert.same(json, in_db)
--            end
--          end)
--
--          it_content_types("updates multiple fields at once", function(content_type)
--            return function()
--              local res = client:patch("/services/" .. route.id, {
--                headers = {
--                  ["Content-Type"] = content_type
--                },
--                body = {
--                  methods = cjson.null,
--                  paths   = { "/my-updated-path" },
--                  hosts   = { "my-updated.tld" },
--                },
--              })
--              local body = assert.res_status(200, res)
--              local json = cjson.decode(body)
--              assert.same({ "/my-updated-path" }, json.paths)
--              assert.same({ "my-updated.tld" }, json.hosts)
--              assert.same(cjson.null, json.methods)
--              assert.equal(route.id, json.id)
--
--              local in_db = assert(db.services:select({id = route.id}))
--              assert.same(json, in_db)
--            end
--          end)
--
--          it("with application/json removes optional field with ngx.null", function()
--            local res = client:patch("/services/" .. route.id, {
--              headers = {
--                ["Content-Type"] = "application/json"
--              },
--              body = {
--                methods = cjson.null,
--                paths   = cjson.null,
--                hosts   = { "my-updated.tld" },
--              },
--            })
--            local body = assert.res_status(200, res)
--            local json = cjson.decode(body)
--            assert.same(cjson.null, json.paths)
--            assert.same({ "my-updated.tld" }, json.hosts)
--            assert.same(cjson.null, json.methods)
--            assert.equal(route.id, json.id)
--
--            local in_db = assert(db.services:select({id = route.id}))
--            assert.same(json, in_db)
--          end)
--
--          describe("errors", function()
--            it_content_types("returns 404 if not found", function(content_type)
--              return function()
--                local res = client:patch("/services/" .. utils.uuid(), {
--                  headers = {
--                    ["Content-Type"] = content_type
--                  },
--                  body = {
--                    methods = cjson.null,
--                    hosts   = cjson.null,
--                    paths   = { "/my-updated-path" },
--                  },
--                })
--                assert.res_status(404, res)
--              end
--            end)
--
--            it_content_types("handles invalid input", function(content_type)
--              return function()
--                local res = client:patch("/services/" .. route.id, {
--                  headers = {
--                    ["Content-Type"] = content_type
--                  },
--                  body = {
--                    regex_priority = "foobar"
--                  },
--                })
--                local body = assert.res_status(400, res)
--                local json = cjson.decode(body)
--                assert.same("expected an integer", json.fields.regex_priority)
--              end
--            end)
--          end)
--        end)
--
--        describe("DELETE", function()
--          it("deletes a route", function()
--            local res  = client:delete("/services/" .. route.id)
--            local body = assert.res_status(204, res)
--            assert.equal("", body)
--
--            local in_db, err = db.services:select({id = route.id})
--            assert.is_nil(err)
--            assert.is_nil(in_db)
--          end)
--
--          describe("errors", function()
--            it("returns HTTP 204 even if not found", function()
--              local res = client:delete("/services/" .. utils.uuid())
--              assert.res_status(204, res)
--            end)
--          end)
--        end)
    end)
  end)
end

