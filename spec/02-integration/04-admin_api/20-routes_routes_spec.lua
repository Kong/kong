local cjson   = require "cjson"
local utils   = require "kong.tools.utils"
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
    local bp
    local db
    local dao
    local client

    setup(function()
      bp, db, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      assert(helpers.start_kong({
        database = strategy,
      }))

      client = assert(helpers.admin_client())
    end)

    after_each(function()
      if client then
        client:close()
      end
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
                message = unindent([[
                  2 schema violations
                  (at least one of these fields must be non-empty: 'methods', 'hosts', 'paths';
                  service: required field missing)
                ]], true, true),
                fields  = {
                  service   = "required field missing",
                  ["@entity"] = {
                    "at least one of these fields must be non-empty: 'methods', 'hosts', 'paths'"
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
                message = "2 schema violations " ..
                          "(protocols: expected one of: http, https; " ..
                          "service: required field missing)",
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
            local pk = { id = "expected a valid UUID" }
            assert.same({
              code    = Errors.codes.INVALID_PRIMARY_KEY,
              name    = "invalid primary key",
              message = [[invalid primary key: '{id="expected a valid UUID"}']],
              fields  = pk
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

        describe("PUT", function()
          it_content_types("creates if not found", function(content_type)
            return function()
              local res = client:put("/routes/" .. route.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  paths   = { "/updated-paths" },
                  service = route.service
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

          it_content_types("updates if found", function(content_type)
            return function()
              local res = client:put("/routes/" .. route.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  paths   = { "/updated-paths" },
                  service = route.service
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

          describe("errors", function()
            it("handles malformed JSON body", function()
              local res = client:put("/routes/" .. route.id, {
                body    = '{"hello": "world"',
                headers = { ["Content-Type"] = "application/json" }
              })
              local body = assert.res_status(400, res)
              assert.equal('{"message":"Cannot parse JSON body"}', body)
            end)


            it_content_types("handles invalid input", function(content_type)
              return function()
                -- Missing params
                local res = client:put("/routes/" .. utils.uuid(), {
                  body = {},
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = unindent([[
                  2 schema violations
                  (at least one of these fields must be non-empty: 'methods', 'hosts', 'paths';
                  service: required field missing)
                ]], true, true),
                  fields  = {
                    service   = "required field missing",
                    ["@entity"] = {
                      "at least one of these fields must be non-empty: 'methods', 'hosts', 'paths'"
                    }
                  }
                }, cjson.decode(body))

                -- Invalid parameter
                res = client:put("/routes/" .. utils.uuid(), {
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
                  message = "2 schema violations " ..
                    "(protocols: expected one of: http, https; " ..
                    "service: required field missing)",
                  fields  = {
                    protocols = "expected one of: http, https",
                    service   = "required field missing",
                  }
                }, cjson.decode(body))

                local res = client:put("/routes/" .. route.id, {
                  headers = {
                    ["Content-Type"] = content_type
                  },
                  body = {
                    service        = route.service,
                    paths          = { "/" },
                    regex_priority = "foobar",
                  },
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = "schema violation (regex_priority: expected an integer)",
                  fields  = {
                    regex_priority = "expected an integer"
                  },
                }, cjson.decode(body))
              end
            end)
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

          it("allows updating sets and arrays with en empty array", function()
            local res = client:patch("/routes/" .. route.id, {
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = {
                methods = {},
                paths   = {},
                hosts   = { "my-updated.tld" },
              },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            if strategy == "cassandra" then
              assert.equals(ngx.null, json.paths)
              assert.equals(ngx.null, json.methods)

            else
              assert.matches('"methods":%[%]', body)
              assert.matches('"paths":%[%]', body)
              assert.same({}, json.paths)
              assert.same({}, json.methods)
            end

            assert.same({ "my-updated.tld" }, json.hosts)
            assert.equal(route.id, json.id)
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
                  message = "schema violation (regex_priority: expected an integer)",
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

      describe("/routes/{route}/service", function()
        local service
        local route

        before_each(function()
          service = bp.services:insert({ host = "example.com", path = "/" })
          route   = bp.routes:insert({ paths = { "/my-route" }, service = service })
        end)

        describe("GET", function()
          it("retrieves by id", function()
            local res  = client:get("/routes/" .. route.id .. "/service")
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(service, json)
          end)

          it("returns 404 if not found", function()
            local res = client:get("/routes/" .. utils.uuid() .. "/service")
            assert.res_status(404, res)
          end)

          it("ignores an invalid body", function()
            local res = client:get("/routes/" .. route.id .. "/service", {
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
              local res = client:patch("/routes/" .. route.id .. "/service", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  name  = "edited",
                  host  = "edited.com",
                  path  = cjson.null,
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("edited",     json.name)
              assert.equal("edited.com", json.host)
              assert.same(cjson.null,    json.path)


              local in_db = assert(db.services:select({ id = service.id }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates with url", function(content_type)
            return function()
              local res = client:patch("/routes/" .. route.id .. "/service", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  url = "http://edited2.com:1234/foo",
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("edited2.com", json.host)
              assert.equal(1234,          json.port)
              assert.equal("/foo",        json.path)


              local in_db = assert(db.services:select({ id = service.id }))
              assert.same(json, in_db)
            end
          end)

          describe("errors", function()
            it_content_types("returns 404 if not found", function(content_type)
              return function()
                local res = client:patch("/routes/" .. utils.uuid() .. "/service", {
                  headers = {
                    ["Content-Type"] = content_type
                  },
                  body = {
                    name  = "edited",
                    host  = "edited.com",
                    path  = cjson.null,
                  },
                })
                assert.res_status(404, res)
              end
            end)

            it_content_types("handles invalid input", function(content_type)
              return function()
                local res = client:patch("/routes/" .. route.id .. "/service", {
                  headers = {
                    ["Content-Type"] = content_type
                  },
                  body = {
                    connect_timeout = "foobar"
                  },
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = "schema violation (connect_timeout: expected an integer)",
                  fields  = {
                    connect_timeout = "expected an integer",
                  },
                }, cjson.decode(body))
              end
            end)
          end)
        end)

        describe("DELETE", function()
          describe("errors", function()
            it("returns HTTP 405 when trying to delete a service that is referenced", function()
              local res  = client:delete("/routes/" .. route.id .. "/service")
              local body = assert.res_status(405, res)
              assert.same({ message = 'Method not allowed' }, cjson.decode(body))
            end)

            it("returns HTTP 404 with non-existing route", function()
              local res = client:delete("/routes/" .. utils.uuid() .. "/service")
              assert.res_status(404, res)
            end)
          end)
        end)
      end)

      describe("/routes/{route}/plugins", function()
        local service
        local route

        before_each(function()
          service = bp.services:insert {
            name     = "my-service",
            protocol = "http",
            host     = "my-service.com",
          }

          route = bp.routes:insert {
            hosts    = { "my-route.com" },
            service  = service
          }
        end)

        describe("POST", function()
          it_content_types("creates a plugin config on a Route", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  name = "key-auth",
                  ["config.key_names"] = "apikey,key"
                },
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(201, res)
              local json = cjson.decode(body)
              assert.equal("key-auth", json.name)
              assert.same({ "apikey", "key" }, json.config.key_names)
            end
          end)

          describe("errors", function()
            it_content_types("handles invalid input", function(content_type)
              return function()
                local res = assert(client:send {
                  method = "POST",
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {},
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                local json = cjson.decode(body)
                assert.same({ name = "name is required" }, json)
              end
            end)

            it_content_types("returns 409 on conflict (same plugin name)", function(content_type)
              return function()
                -- insert initial plugin
                local res = assert(client:send {
                  method = "POST",
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {
                    name = "basic-auth",
                  },
                  headers = {["Content-Type"] = content_type}
                })
                assert.response(res).has.status(201)
                assert.response(res).has.jsonbody()

                -- do it again, to provoke the error
                local res = assert(client:send {
                  method = "POST",
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {
                    name = "basic-auth",
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                assert.response(res).has.status(409)
                local json = assert.response(res).has.jsonbody()
                assert.same({ name = "already exists with value 'basic-auth'"}, json)
              end
            end)

            it_content_types("returns 409 on id conflict (same plugin id)", function(content_type)
              return function()
                -- insert initial plugin
                local res = assert(client:send {
                  method = "POST",
                  path = "/routes/"..route.id.."/plugins",
                  body = {
                    name = "basic-auth",
                  },
                  headers = {["Content-Type"] = content_type}
                })
                local body = assert.res_status(201, res)
                local plugin = cjson.decode(body)

                -- do it again, to provoke the error
                local conflict_res = assert(client:send {
                  method = "POST",
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {
                    name = "key-auth",
                    id = plugin.id,
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                local conflict_body = assert.res_status(409, conflict_res)
                local json = cjson.decode(conflict_body)
                assert.same({ id = "already exists with value '" .. plugin.id .. "'"}, json)
              end
            end)
          end)
        end)

        describe("PUT", function()
          it_content_types("creates if not exists", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  name = "key-auth",
                  ["config.key_names"] = "apikey,key",
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(201, res)
              local json = cjson.decode(body)
              assert.equal("key-auth", json.name)
              assert.same({ "apikey", "key" }, json.config.key_names)
            end
          end)

          it_content_types("replaces if exists", function(content_type)
            return function()
              local res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  name = "key-auth",
                  ["config.key_names"] = "apikey,key",
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(201, res)
              local json = cjson.decode(body)

              res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  id = json.id,
                  name = "key-auth",
                  ["config.key_names"] = "key",
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(200, res)
              json = cjson.decode(body)
              assert.equal("key-auth", json.name)
              assert.same({ "key" }, json.config.key_names)
            end
          end)

          it_content_types("perfers default values when replacing", function(content_type)
            return function()
              local plugin = assert(dao.plugins:insert {
                name = "key-auth",
                route_id = route.id,
                config = {hide_credentials = true}
              })
              assert.True(plugin.config.hide_credentials)
              assert.same({"apikey"}, plugin.config.key_names)

              local res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  id = plugin.id,
                  name = "key-auth",
                  ["config.key_names"] = "apikey,key",
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
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
                route_id = route.id
              })
              assert.same({ "apikey" }, plugin.config.key_names)

              local res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  id = plugin.id,
                  name = "key-auth",
                  ["config.key_names"] = "apikey,key",
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "apikey", "key" }, json.config.key_names)
            end
          end)

          it_content_types("updates the enabled property", function(content_type)
            return function()
              local plugin = assert(dao.plugins:insert {
                name = "key-auth",
                route_id = route.id
              })
              assert.True(plugin.enabled)

              local res = assert(client:send {
                method = "PUT",
                path = "/routes/" .. route.id .. "/plugins",
                body = {
                  id = plugin.id,
                  name = "key-auth",
                  enabled = false,
                  created_at = 1461276890000
                },
                headers = { ["Content-Type"] = content_type }
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
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {},
                  headers = { ["Content-Type"] = content_type }
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
            assert(dao.plugins:insert {
              name = "key-auth",
              route_id = route.id
            })
            local res = assert(client:send {
              method = "GET",
              path = "/routes/" .. route.id .. "/plugins"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(1, #json.data)
          end)

          it("ignores an invalid body", function()
            local res = assert(client:send {
              method = "GET",
              path = "/routes/" .. route.id .. "/plugins",
              body = "this fails if decoded as json",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(200, res)
          end)
        end)
      end)
    end)
  end)
end
