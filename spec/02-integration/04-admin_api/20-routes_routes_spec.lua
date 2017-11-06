local DB      = require "kong.db"
local cjson   = require "cjson"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"
local Blueprints = require "spec.fixtures.blueprints"


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_json = fn("application/json")
  it(title .. " with application/json", test_json)
  it(title .. " with application/www-form-urlencoded", test_form_encoded)
end


for _, strategy in helpers.each_strategy("postgres") do
  describe("Admin API #" .. strategy, function()
    local db
    local client
    local bp

    setup(function()
      do
        -- old DAO to run the migrations
        local test_conf = helpers.test_conf
        local old_strategy = test_conf.database
        test_conf.database = strategy

        local DAOFactory = require "kong.dao.factory"
        local dao = assert(DAOFactory.new(test_conf))
        assert(dao:run_migrations())

        test_conf.database = old_strategy
      end

      db = assert(DB.new(helpers.test_conf, strategy))
      assert(db:init_connector())

      assert(helpers.start_kong({
        database = strategy,
      }))

      client = assert(helpers.admin_client())
      bp = Blueprints.new({}, db)
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

    describe("/routes", function()
      describe("POST", function()
        it_content_types("creates a route", function(content_type)
          return function()
            local res = client:post("/routes", {
              body = {
                protocols = { "http" },
                hosts     = { "my.route.com" },
                service   = bp.services:insert(),
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "my.route.com" }, json.hosts)
            assert.is_number(json.created_at)
            assert.is_number(json.regex_priority)
            assert.is_string(json.id)
            assert.equals(cjson.null, json.paths)
            assert.False(json.preserve_host)
            assert.True(json.strip_path)
          end
        end)

        it_content_types("creates a complex route", function(content_type)
          return function()
            local s = bp.services:insert()
            local res = client:post("/routes", {
              body    = {
                protocols = { "http" },
                methods   = { "GET", "POST", "PATCH" },
                hosts     = { "foo.api.com", "bar.api.com" },
                paths     = { "/foo", "/bar" },
                service   = { id = s.id },
              },
              headers = { ["Content-Type"] = content_type }
            })

            -- TODO: For some reason the body which arrives to the server is
            -- incorrectly parsed on this test: self.params.methods is the string
            -- "PATCH" instead of an array, for example. I could not find the
            -- cause

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
            assert.same({ "/foo","/bar" }, json.paths)
            assert.same({ "GET", "POST", "PATCH" }, json.methods)
            assert.same(s.id, json.service.id)
          end
        end)

        describe("errors", function()
          it("handles malformed JSON body", function()
            local res = client:post("/routes", {
              body    = '{"hello": "world"',
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(400, res)
            assert.equal('{"message":"Cannot parse JSON body"}', body)
          end)

          it_content_types("handles invalid input", function(content_type)
            return function()
              -- Missing params
              local res = client:post("/routes", {
                body = {},
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = cjson.null,
                fields  = {
                  service   = "required field missing",
                  ["@entity"] = {
                    at_least_one_of = "at least one of 'methods', 'hosts' or 'paths' must be non-empty"
                  }
                }
              }, cjson.decode(body))

              -- Invalid parameter
              res = client:post("/routes", {
                body = {
                  methods   = { "GET" },
                  protocols = { "foo" },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = cjson.null,
                fields  = {
                  protocols = "expected one of: http, https",
                  service   = "required field missing",
                }
              }, cjson.decode(body))
            end
          end)
        end)
      end)


      describe("GET", function()
        describe("with data", function()
          before_each(function()
            for i = 1, 10 do
              bp.routes:insert({ paths = { "/route-" .. i } })
            end
          end)

          it("retrieves the first page", function()
            local res = assert(client:send {
              method = "GET",
              path   = "/routes"
            })
            local res = assert.res_status(200, res)
            local json = cjson.decode(res)
            assert.equal(10, #json.data)
          end)

          it("paginates a set", function()
            local pages = {}
            local offset

            for i = 1, 4 do
              local res = assert(client:send {
                method = "GET",
                path   = "/routes",
                query  = { size = 3, offset = offset }
              })
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
            local res = assert(client:send {
              method = "GET",
              path = "/routes"
            })
            local body = assert.res_status(200, res)
            assert.matches('"data":%[%]', body)
            local json = cjson.decode(body)
            assert.same({ data = {}, next = cjson.null }, json)
          end)
        end)

        describe("errors", function()
          it("handles invalid filters", function()
            local res = assert(client:send {
              method = "GET",
              path = "/routes",
              query = {foo = "bar"}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({ data = {}, next = cjson.null }, json)
          end)

          it("handles invalid offsets", function()
            local res  = client:get("/routes", { query = { offset = "x" } })
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.INVALID_OFFSET,
              name    = "invalid offset",
              message = "'x' is not a valid offset for this strategy: bad base64 encoding"
            }, cjson.decode(body))

            res  = client:get("/routes", { query = { offset = "potato" } })
            body = assert.res_status(400, res)

            local json = cjson.decode(body)
            json.message = nil

            assert.same({
              code    = Errors.codes.INVALID_OFFSET,
              name    = "invalid offset",
            }, json)
          end)

          it("ignores an invalid body", function()
            local res = assert(client:send {
              method = "GET",
              path = "/routes",
              body = "this fails if decoded as json",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(200, res)
          end)

          it("validates invalid primary keys", function()
            local res  = assert(client:get("/routes/foobar"))
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.INVALID_PRIMARY_KEY,
              name    = "invalid primary key",
              message = cjson.null,
              fields  = {
                id = "expected a valid UUID",
              },
            }, cjson.decode(body))
          end)
        end)
      end)


      it("returns HTTP 405 on invalid method", function()
        local methods = { "DELETE", "PUT", "PATCH" }

        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/routes",
            body = {}, -- tmp: body to allow POST/PUT to work
            headers = {
              ["Content-Type"] = "application/json"
            }
          })
          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("/routes/{route}", function()
        local route

        before_each(function()
          route = bp.routes:insert({ paths = { "/my-route" } })
        end)

        describe("GET", function()
          it("retrieves by id", function()
            local res  = client:get("/routes/" .. route.id)
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(route, json)
          end)

          it("returns 404 if not found", function()
            local res = client:get("/routes/" .. utils.uuid())
            assert.res_status(404, res)
          end)

          it("ignores an invalid body", function()
            local res = client:get("/routes/" .. route.id, {
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = "this fails if decoded as json",
            })
            assert.res_status(200, res)
          end)
        end)

        describe("PATCH", function()
          it_content_types("updates if found", function(content_type)
            return function()
              local res = client:patch("/routes/" .. route.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  methods = cjson.null,
                  hosts   = cjson.null,
                  paths   = { "/updated-paths" },
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/updated-paths" }, json.paths)
              assert.same(cjson.null, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.equal(route.id, json.id)

              local in_db = assert(db.routes:select({ id = route.id }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates strip_path if not previously set", function(content_type)
            return function()
              local res = client:patch("/routes/" .. route.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  strip_path = true
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.True(json.strip_path)
              assert.equal(route.id, json.id)

              local in_db = assert(db.routes:select({id = route.id}))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates multiple fields at once", function(content_type)
            return function()
              local res = client:patch("/routes/" .. route.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  methods = cjson.null,
                  paths   = { "/my-updated-path" },
                  hosts   = { "my-updated.tld" },
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/my-updated-path" }, json.paths)
              assert.same({ "my-updated.tld" }, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.equal(route.id, json.id)

              local in_db = assert(db.routes:select({id = route.id}))
              assert.same(json, in_db)
            end
          end)

          it("with application/json removes optional field with ngx.null", function()
            local res = client:patch("/routes/" .. route.id, {
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {
                methods = cjson.null,
                paths   = cjson.null,
                hosts   = { "my-updated.tld" },
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(cjson.null, json.paths)
            assert.same({ "my-updated.tld" }, json.hosts)
            assert.same(cjson.null, json.methods)
            assert.equal(route.id, json.id)

            local in_db = assert(db.routes:select({id = route.id}))
            assert.same(json, in_db)
          end)

          describe("errors", function()
            it_content_types("returns 404 if not found", function(content_type)
              return function()
                local res = client:patch("/routes/" .. utils.uuid(), {
                  headers = {
                    ["Content-Type"] = content_type
                  },
                  body = {
                    methods = cjson.null,
                    hosts   = cjson.null,
                    paths   = { "/my-updated-path" },
                  },
                })
                assert.res_status(404, res)
              end
            end)

            it_content_types("handles invalid input", function(content_type)
              return function()
                local res = client:patch("/routes/" .. route.id, {
                  headers = {
                    ["Content-Type"] = content_type
                  },
                  body = {
                    regex_priority = "foobar"
                  },
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = cjson.null ,
                  fields  = {
                    regex_priority = "expected an integer"
                  },
                }, cjson.decode(body))
              end
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes a route", function()
            local res  = client:delete("/routes/" .. route.id)
            local body = assert.res_status(204, res)
            assert.equal("", body)

            local in_db, err = db.routes:select({id = route.id})
            assert.is_nil(err)
            assert.is_nil(in_db)
          end)

          describe("errors", function()
            it("returns HTTP 204 even if not found", function()
              local res = client:delete("/routes/" .. utils.uuid())
              assert.res_status(204, res)
            end)
          end)
        end)
      end)
    end)
  end)
end
