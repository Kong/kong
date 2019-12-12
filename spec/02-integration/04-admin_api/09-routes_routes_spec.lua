local cjson   = require "cjson"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"


local unindent = helpers.unindent


local function it_content_types(title, fn)
  local test_form_encoded = fn("application/x-www-form-urlencoded")
  local test_multipart = fn("multipart/form-data")
  local test_json = fn("application/json")

  it(title .. " with application/www-form-urlencoded", test_form_encoded)
  it(title .. " with multipart/form-data", test_multipart)
  it(title .. " with application/json", test_json)
end


for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy, function()
    local bp
    local db
    local client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      })
      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
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
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local res = client:post("/routes", {
              body = {
                protocols = { "http" },
                hosts     = { "my.route.com" },
                headers   = { location = { "my-location" } },
                service   = bp.services:insert(),
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "my.route.com" }, json.hosts)
            assert.same({ location = { "my-location" } }, json.headers)
            assert.is_number(json.created_at)
            assert.is_number(json.regex_priority)
            assert.is_string(json.id)
            assert.equals(cjson.null, json.name)
            assert.equals(cjson.null, json.paths)
            assert.False(json.preserve_host)
            assert.True(json.strip_path)
          end
        end)

        it_content_types("creates a route #grpc", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local res = client:post("/routes", {
              body = {
                protocols = { "grpc", "grpcs" },
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
            assert.equals(cjson.null, json.name)
            assert.equals(cjson.null, json.paths)
            assert.False(json.preserve_host)
            assert.False(json.strip_path)
            assert.same({ "grpc", "grpcs" }, json.protocols)
          end
        end)

        it_content_types("creates a route without service", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local res = client:post("/routes", {
              body = {
                protocols = { "http" },
                hosts     = { "my.route.com" },
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "my.route.com" }, json.hosts)
            assert.is_number(json.created_at)
            assert.is_number(json.regex_priority)
            assert.is_string(json.id)
            assert.equals(cjson.null, json.name)
            assert.equals(cjson.null, json.paths)
            assert.equals(cjson.null, json.service)
            assert.False(json.preserve_host)
            assert.True(json.strip_path)
          end
        end)

        it_content_types("creates a route without service #grpc", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local res = client:post("/routes", {
              body = {
                protocols = { "grpc", "grpcs" },
                hosts     = { "my.route.com" },
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "my.route.com" }, json.hosts)
            assert.is_number(json.created_at)
            assert.is_number(json.regex_priority)
            assert.is_string(json.id)
            assert.equals(cjson.null, json.name)
            assert.equals(cjson.null, json.paths)
            assert.equals(cjson.null, json.service)
            assert.False(json.preserve_host)
            assert.False(json.strip_path)
            assert.same({ "grpc", "grpcs" }, json.protocols)
          end
        end)

        it_content_types("creates a complex route", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

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

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
            assert.same({ "/foo","/bar" }, json.paths)
            assert.same({ "GET", "POST", "PATCH" }, json.methods)
            assert.same(s.id, json.service.id)
          end
        end)

        it_content_types("creates a complex route #grpc", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local s = bp.services:insert()
            local res = client:post("/routes", {
              body    = {
                protocols = { "grpc", "grpcs" },
                hosts     = { "foo.api.com", "bar.api.com" },
                paths     = { "/foo", "/bar" },
                service   = { id = s.id },
              },
              headers = { ["Content-Type"] = content_type }
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
            assert.same({ "/foo","/bar" }, json.paths)
            assert.same(s.id, json.service.id)
            assert.same({ "grpc", "grpcs"}, json.protocols)
          end
        end)

        it_content_types("creates a complex route by referencing a service by name", function(content_type, name)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local s = bp.named_services:insert()
            local res = client:post("/routes", {
              body    = {
                protocols = { "http" },
                methods   = { "GET", "POST", "PATCH" },
                hosts     = { "foo.api.com", "bar.api.com" },
                paths     = { "/foo", "/bar" },
                service   = { name = s.name },
              },
              headers = { ["Content-Type"] = content_type }
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
            assert.same({ "/foo","/bar" }, json.paths)
            assert.same({ "GET", "POST", "PATCH" }, json.methods)
            assert.same(s.id, json.service.id)
          end
        end)

        it_content_types("creates a complex route by referencing a service by name #grpc", function(content_type, name)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local s = bp.named_services:insert()
            local res = client:post("/routes", {
              body    = {
                protocols = { "grpc", "grpcs" },
                hosts     = { "foo.api.com", "bar.api.com" },
                paths     = { "/foo", "/bar" },
                service   = { name = s.name },
              },
              headers = { ["Content-Type"] = content_type }
            })

            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "foo.api.com", "bar.api.com" }, json.hosts)
            assert.same({ "/foo","/bar" }, json.paths)
            assert.same(s.id, json.service.id)
            assert.same({ "grpc", "grpcs"}, json.protocols)
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
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

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
                  schema violation
                  (must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https')
                ]], true, true),
                fields  = {
                  ["@entity"] = {
                    "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'",
                  }
                }
              }, cjson.decode(body))

              -- Missing https params
              res = client:post("/routes", {
                body = {
                  protocols = { "https" },
                },
                headers = { ["content-type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = unindent([[
                  schema violation
                  (must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https')
                ]], true, true),
                fields  = {
                  ["@entity"] = {
                    "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'"
                  }
                }
              }, cjson.decode(body))

              -- Invalid parameter
              res = client:post("/routes", {
                body = {
                  methods   = { "GET" },
                  protocols = { "foo", "http" },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = "schema violation " ..
                          "(protocols.1: expected one of: grpc, grpcs, http, https, tcp, tls)",
                fields = {
                  protocols = { "expected one of: grpc, grpcs, http, https, tcp, tls" },
                }
              }, cjson.decode(body))

              -- Invalid foreign entity
              res = client:post("/routes", {
                body = {
                  methods   = { "GET" },
                  protocols = { "foo", "http" },
                  service = { name = [[\o/]] },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = "2 schema violations " ..
                  "(protocols.1: expected one of: grpc, grpcs, http, https, tcp, tls; " ..
                  [[service.name: invalid value '\o/': it must only contain alphanumeric and '., -, _, ~' characters)]],
                fields = {
                  protocols = { "expected one of: grpc, grpcs, http, https, tcp, tls" },
                  service = {
                    name = [[invalid value '\o/': it must only contain alphanumeric and '., -, _, ~' characters]]
                  }
                }
              }, cjson.decode(body))

              -- Invalid foreign entity reference
              res = client:post("/routes", {
                body = {
                  methods   = { "GET" },
                  service = { name = "non-existing" },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.FOREIGN_KEYS_UNRESOLVED,
                name    = "foreign keys unresolved",
                message = [[foreign key unresolved (service.name: the foreign key cannot be resolved with ]] ..
                          [['{name="non-existing"}' for an existing 'services' entity)]],
                fields = {
                  service = {
                    name = [[the foreign key cannot be resolved with '{name="non-existing"}' ]] ..
                           [[for an existing 'services' entity]]
                  }
                }
              }, cjson.decode(body))

              local service_name = content_type == "application/json" and cjson.null or ""
              -- Invalid foreign entity reference
              res = client:post("/routes", {
                body = {
                  methods = { "GET" },
                  service = { name = service_name },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = "schema violation " ..
                  "(service.id: missing primary key)",
                fields = {
                  service = {
                    id = "missing primary key"
                  }
                }
              }, cjson.decode(body))


              -- Foreign entity cannot be resolved
              res = client:post("/routes", {
                body = {
                  methods   = { "GET" },
                  service = { protocol = "http" },
                },
                headers = { ["Content-Type"] = content_type }
              })
              body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = "schema violation " ..
                          "(service.id: missing primary key)",
                fields = {
                  service = {
                    id = "missing primary key"
                  }
                }
              }, cjson.decode(body))
            end
          end)
        end)
      end)

      describe("GET", function()
        describe("with data", function()
          lazy_setup(function()
            db:truncate("routes")
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
          lazy_setup(function()
            db:truncate("routes")
          end)
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

          it("handles invalid size", function()
            local res  = client:get("/routes", { query = { size = "x" } })
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.INVALID_SIZE,
              name    = "invalid size",
              message = "size must be a number"
            }, cjson.decode(body))

            res  = client:get("/routes", { query = { size = "potato" } })
            body = assert.res_status(400, res)

            local json = cjson.decode(body)
            json.message = nil

            assert.same({
              code    = Errors.codes.INVALID_SIZE,
              name    = "invalid size",
            }, json)
          end)

          it("handles invalid offsets", function()
            local res  = client:get("/routes", { query = { offset = "x" } })
            local body = assert.res_status(400, res)
            assert.same({
              code    = Errors.codes.INVALID_OFFSET,
              name    = "invalid offset",
              message = "'x' is not a valid offset: bad base64 encoding"
            }, cjson.decode(body))

            res  = client:get("/routes", { query = { offset = "|potato|" } })
            body = assert.res_status(400, res)

            local json = cjson.decode(body)
            json.message = nil

            assert.same({
              code = Errors.codes.INVALID_OFFSET,
              name = "invalid offset",
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
        describe("GET", function()
          it("retrieves by id", function()
            local route = bp.routes:insert({ paths = { "/my-route" } }, { nulls = true })
            local res  = client:get("/routes/" .. route.id)
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(route, json)
          end)

          it("retrieves by name", function()
            local route = bp.named_routes:insert(nil, { nulls = true })
            local res  = client:get("/routes/" .. route.name)
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(route, json)
          end)

          it("returns 404 if not found", function()
            local res = client:get("/routes/" .. utils.uuid())
            assert.res_status(404, res)
          end)

          it("returns 404 if not found by name", function()
            local res = client:get("/routes/not-found")
            assert.res_status(404, res)
          end)

          it("ignores an invalid body", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })
            local res = client:get("/routes/" .. route.id, {
              headers = {
                ["Content-Type"] = "application/json"
              },
              body = "this fails if decoded as json",
            })
            assert.res_status(200, res)
          end)

          it("ignores an invalid body by name", function()
            local route = bp.named_routes:insert()
            local res = client:get("/routes/" .. route.name, {
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
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local service = bp.services:insert()
              local id = utils.uuid()
              local res = client:put("/routes/" .. id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  paths   = { "/updated-paths" },
                  service = service
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/updated-paths" }, json.paths)
              assert.same(cjson.null, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.equal(id, json.id)

              local in_db = assert(db.routes:select({ id = id }, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("creates without service if not found", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local id = utils.uuid()
              local res = client:put("/routes/" .. id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  paths   = { "/updated-paths" },
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/updated-paths" }, json.paths)
              assert.same(cjson.null, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.same(cjson.null, json.service)
              assert.equal(id, json.id)

              local in_db = assert(db.routes:select({ id = id }, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("creates if not found by name", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local service = bp.services:insert()
              local name = "my-route"
              local res = client:put("/routes/" .. name, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  paths   = { "/updated-paths" },
                  service = service
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/updated-paths" }, json.paths)
              assert.same(cjson.null, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.equal(name, json.name)

              local in_db = assert(db.routes:select_by_name(name, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates if found", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({ paths = { "/my-route" } })
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

              local in_db = assert(db.routes:select({ id = route.id }, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates if found by name", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({
                name  = "my-put-route",
                paths = { "/my-route" }
              })
              local res = client:put("/routes/my-put-route", {
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
              assert.equal(route.name, json.name)

              local in_db = assert(db.routes:select_by_name(route.name, { nulls = true }))
              assert.same(json, in_db)

              db.routes:delete({ id = route.id })
            end
          end)

          it_content_types("handles same parameter in url and params gracefully", function(content_type)
            return function()
              local res = client:put("/routes/my-put-route", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  routes = {
                    test = {
                      {
                        test = "test",
                      }
                    }
                  },
                  tags = "test",
                },
              })

              assert.res_status(400, res)
            end
          end)

          describe("errors", function()
            it("handles malformed JSON body", function()
              local route = bp.routes:insert({ paths = { "/my-route" } })
              local res = client:put("/routes/" .. route.id, {
                body    = '{"hello": "world"',
                headers = { ["Content-Type"] = "application/json" }
              })
              local body = assert.res_status(400, res)
              assert.equal('{"message":"Cannot parse JSON body"}', body)
            end)


            it_content_types("handles invalid input", function(content_type)
              return function()
                if content_type == "multipart/form-data" then
                  -- the client doesn't play well with this
                  return
                end

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
                  schema violation
                  (must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https')
                ]], true, true),
                  fields  = {
                    ["@entity"] = {
                      "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'"
                    }
                  }
                }, cjson.decode(body))

                -- Invalid parameter
                res = client:put("/routes/" .. utils.uuid(), {
                  body = {
                    methods   = { "GET" },
                    protocols = { "foo", "http" },
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = "schema violation " ..
                    "(protocols.1: expected one of: grpc, grpcs, http, https, tcp, tls)",
                  fields  = {
                    protocols = { "expected one of: grpc, grpcs, http, https, tcp, tls" },
                  }
                }, cjson.decode(body))

                local route = bp.routes:insert({ paths = { "/my-route" } })
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

            it_content_types("handles invalid input #grpc", function(content_type)
              return function()
                if content_type == "multipart/form-data" then
                  -- the client doesn't play well with this
                  return
                end

                -- Missing grpc/grpcs routing attributes
                local res = client:post("/routes", {
                  body = {
                    protocols = { "grpc", "grpcs" },
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = unindent([[
                  schema violation
                  (must set one of 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'grpcs')
                  ]], true, true),
                  fields  = {
                    ["@entity"] = {
                      "must set one of 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'grpcs'",
                    }
                  }
                }, cjson.decode(body))

                -- Doesn't accept 'strip_path' attribute
                local res = client:post("/routes", {
                  body = {
                    protocols = { "grpc", "grpcs" },
                    paths = { "/" },
                    strip_path = true,
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = unindent([[
                  schema violation (strip_path: cannot set 'strip_path' when 'protocols' is 'grpc' or 'grpcs')
                  ]], true, true),
                  fields  = {
                    strip_path = "cannot set 'strip_path' when 'protocols' is 'grpc' or 'grpcs'",
                  }
                }, cjson.decode(body))

                -- Doesn't accept 'methods' attribute
                local res = client:post("/routes", {
                  body = {
                    protocols = { "grpc", "grpcs" },
                    paths = { "/" },
                    methods = { "GET" }
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                assert.same({
                  code    = Errors.codes.SCHEMA_VIOLATION,
                  name    = "schema violation",
                  message = unindent([[
                  schema violation (methods: cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs')
                  ]], true, true),
                  fields  = {
                    methods = "cannot set 'methods' when 'protocols' is 'grpc' or 'grpcs'",
                  }
                }, cjson.decode(body))
              end
            end)
          end)
        end)

        describe("PATCH", function()
          it_content_types("updates if found", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({ paths = { "/my-route" } })
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

              local in_db = assert(db.routes:select({ id = route.id }, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates if found by name", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({
                name  = "my-patch-route",
                paths = { "/my-route" },
              })
              local res = client:patch("/routes/my-patch-route", {
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

              local in_db = assert(db.routes:select({ id = route.id }, { nulls = true }))
              assert.same(json, in_db)

              db.routes:delete({ id = route.id })
            end
          end)

          it_content_types("updates strip_path if not previously set", function(content_type)
            return function()
              local route = bp.routes:insert({ paths = { "/my-route" } })
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

              local in_db = assert(db.routes:select({id = route.id}, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates multiple fields at once", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({ paths = { "/my-route" } })
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

              local in_db = assert(db.routes:select({id = route.id}, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it("with application/json removes optional field with ngx.null", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })
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

            local in_db = assert(db.routes:select({id = route.id}, { nulls = true }))
            assert.same(json, in_db)
          end)

          it("allows updating sets and arrays with en empty array", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })
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

          it_content_types("removes service association", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({
                name  = "my-patch-route",
                paths = { "/my-route" },
              })
              local res = client:patch("/routes/my-patch-route", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  methods = cjson.null,
                  hosts   = cjson.null,
                  service = cjson.null,
                  paths   = { "/updated-paths" },
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same({ "/updated-paths" }, json.paths)
              assert.same(cjson.null, json.hosts)
              assert.same(cjson.null, json.methods)
              assert.same(cjson.null, json.service)
              assert.equal(route.id, json.id)

              local in_db = assert(db.routes:select({ id = route.id }, { nulls = true }))
              assert.same(json, in_db)

              db.routes:delete({ id = route.id })
            end
          end)

          describe("errors", function()
            it_content_types("returns 404 if not found", function(content_type)
              return function()
                if content_type == "multipart/form-data" then
                  -- the client doesn't play well with this
                  return
                end

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
                local route = bp.routes:insert({ paths = { "/my-route" } })
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
            local route = bp.routes:insert({ paths = { "/my-route" } })
            local res  = client:delete("/routes/" .. route.id)
            local body = assert.res_status(204, res)
            assert.equal("", body)

            local in_db, err = db.routes:select({id = route.id}, { nulls = true })
            assert.is_nil(err)
            assert.is_nil(in_db)
          end)

          it("deletes a route by name", function()
            local route = bp.routes:insert({
              name  = "my-delete-route",
              paths = { "/my-route" }
            })
            local res  = client:delete("/routes/my-delete-route")
            local body = assert.res_status(204, res)
            assert.equal("", body)

            local in_db, err = db.routes:select({id = route.id}, { nulls = true })
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

        describe("GET", function()
          it("retrieves by id", function()
            local service = bp.services:insert({ host = "example.com", path = "/" }, { nulls = true })
            local route = bp.routes:insert({ paths = { "/my-route" }, service = service })

            local res  = client:get("/routes/" .. route.id .. "/service")
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(service, json)
          end)

          it("retrieves by name", function()
            local service = bp.services:insert({ host = "example.com", path = "/" }, { nulls = true })
            bp.routes:insert({ name = "my-get-route", paths = { "/my-route" }, service = service })

            local res  = client:get("/routes/my-get-route/service")
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(service, json)
          end)

          it("returns 404 if not found", function()
            local res = client:get("/routes/" .. utils.uuid() .. "/service")
            assert.res_status(404, res)
          end)

          it("returns 404 if not found by name", function()
            local res = client:get("/routes/my-in-existent-route/service")
            assert.res_status(404, res)
          end)

          it("ignores an invalid body", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })

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
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local service = bp.named_services:insert({ path = "/" })
              local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
              local edited_name = "name-" .. service.name
              local edited_host = "edited-" .. service.host
              local res = client:patch("/routes/" .. route.id .. "/service", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  name  = edited_name,
                  host  = edited_host,
                  path  = cjson.null,
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal(edited_name, json.name)
              assert.equal(edited_host, json.host)
              assert.same(cjson.null,   json.path)


              local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
              assert.same(json, in_db)
            end
          end)

          it_content_types("updates if found by name", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local service = bp.named_services:insert({ path = "/" })
              local route = bp.routes:insert({ name = "my-service-patch-route", paths = { "/my-route" }, service = service })
              local edited_name = "name-" .. service.name
              local edited_host = "edited-" .. service.host
              local res = client:patch("/routes/my-service-patch-route/service", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  name  = edited_name,
                  host  = edited_host,
                  path  = cjson.null,
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal(edited_name, json.name)
              assert.equal(edited_host, json.host)
              assert.same(cjson.null,   json.path)


              local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
              assert.same(json, in_db)

              db.routes:delete({ id = route.id })
              db.services:delete({ id = service.id })
            end
          end)

          it_content_types("updates with url", function(content_type)
            return function()
              local service = bp.services:insert({ host = "example.com", path = "/" })
              local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
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


              local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
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
                local service = bp.services:insert({ host = "example.com", path = "/" })
                local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
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
              local route = bp.routes:insert({ paths = { "/my-route" } })
              local res  = client:delete("/routes/" .. route.id .. "/service")
              local body = assert.res_status(405, res)
              assert.same({ message = 'Method not allowed' }, cjson.decode(body))
            end)

            it("returns HTTP 404 with non-existing route", function()
              local res = client:delete("/routes/" .. utils.uuid() .. "/service")
              assert.res_status(404, res)
            end)

            it("returns HTTP 404 with non-existing route by name", function()
              local res = client:delete("/routes/in-existent-route/service")
              assert.res_status(404, res)
            end)
          end)
        end)
      end)

      describe("PUT", function()
        it_content_types("creates if not found", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local route = bp.routes:insert({ paths = { "/my-route" } })
            local res = client:put("/routes/" .. route.id .. "/service", {
              headers = {
                ["Content-Type"] = content_type
              },
              body = {
                url = "http://httpbin.org",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same("httpbin.org", json.host)

            local in_db = assert(db.services:select({ id = json.id }, { nulls = true }))
            assert.same(json, in_db)
          end
        end)

        it_content_types("updates if found", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local service = bp.named_services:insert({ path = "/" })
            local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
            local edited_name = "name-" .. service.name
            local edited_host = "edited-" .. service.host
            local res = client:put("/routes/" .. route.id .. "/service", {
              headers = {
                ["Content-Type"] = content_type
              },
              body = {
                name  = edited_name,
                host  = edited_host,
                path  = cjson.null,
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(edited_name, json.name)
            assert.equal(edited_host, json.host)
            assert.same(cjson.null,   json.path)


            local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
            assert.same(json, in_db)
          end
        end)

        it_content_types("updates if found by name", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local service = bp.named_services:insert({ path = "/" })
            local route = bp.routes:insert({ name = "my-service-patch-route", paths = { "/my-route" }, service = service })
            local edited_name = "name-" .. service.name
            local edited_host = "edited-" .. service.host
            local res = client:put("/routes/my-service-patch-route/service", {
              headers = {
                ["Content-Type"] = content_type
              },
              body = {
                name  = edited_name,
                host  = edited_host,
                path  = cjson.null,
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(edited_name, json.name)
            assert.equal(edited_host, json.host)
            assert.same(cjson.null,   json.path)


            local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
            assert.same(json, in_db)

            db.routes:delete({ id = route.id })
            db.services:delete({ id = service.id })
          end
        end)

        it_content_types("updates with url", function(content_type)
          return function()
            local service = bp.services:insert({ host = "example.com", path = "/" })
            local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
            local res = client:put("/routes/" .. route.id .. "/service", {
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


            local in_db = assert(db.services:select({ id = service.id }, { nulls = true }))
            assert.same(json, in_db)
          end
        end)

        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = client:put("/routes/" .. utils.uuid() .. "/service", {
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
              local service = bp.services:insert({ host = "example.com", path = "/" })
              local route = bp.routes:insert({ paths = { "/my-route" }, service = service })
              local res = client:put("/routes/" .. route.id .. "/service", {
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
                message = "2 schema violations (connect_timeout: expected an integer; host: required field missing)",
                fields  = {
                  connect_timeout = "expected an integer",
                  host = "required field missing",
                },
              }, cjson.decode(body))
            end
          end)
        end)
      end)

      describe("/routes/{route}/plugins", function()
        describe("POST", function()
          it_content_types("creates a plugin config on a Route", function(content_type)
            return function()
              if content_type == "multipart/form-data" then
                -- the client doesn't play well with this
                return
              end

              local route = bp.routes:insert({ paths = { "/my-route" } })
              local bodies = {
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
                path = "/routes/" .. route.id .. "/plugins",
                body = bodies[content_type],
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
                local route = bp.routes:insert({ paths = { "/my-route" } })
                local res = assert(client:send {
                  method = "POST",
                  path = "/routes/" .. route.id .. "/plugins",
                  body = {},
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(400, res)
                local json = cjson.decode(body)
                assert.same({
                  code = 2,
                  fields = {
                    name = "required field missing",
                  },
                  message = "schema violation (name: required field missing)",
                  name = "schema violation",
                }, json)
              end
            end)

            it_content_types("returns 409 on conflict (same plugin name)", function(content_type)
              return function()
                local route = bp.routes:insert({ paths = { "/my-route" } })
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
                assert.same({
                  code = 5,
                  fields = {
                    consumer = ngx.null,
                    name = "basic-auth",
                    route = {
                      id = route.id,
                    },
                    service = ngx.null,
                  },
                  message = [[UNIQUE violation detected on '{consumer=null,]] ..
                            [[name="basic-auth",route={id="]] ..
                            route.id .. [["},service=null}']],
                  name = "unique constraint violation",
                }, json)
              end
            end)

            -- Cassandra doesn't fail on this because its insert is an upsert
            pending("returns 409 on id conflict (same plugin id)", function(content_type)
              return function()
                local route = bp.routes:insert({ paths = { "/my-route" } })
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
                ngx.sleep(1)
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
                assert.same({
                  code = Errors.codes.PRIMARY_KEY_VIOLATION,
                  fields = {
                    id = plugin.id,
                  },
                  message = [[primary key violation on key '{id="]] ..
                            plugin.id .. [["}']],
                  name = "primary key violation",
                }, json)
              end
            end)
          end)
        end)

        describe("GET", function()
          it("retrieves the first page", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })
            assert(db.plugins:insert {
              name = "key-auth",
              route = { id = route.id },
            })
            local res = assert(client:send {
              method = "GET",
              path = "/routes/" .. route.id .. "/plugins"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(1, #json.data)
          end)

          it("retrieves the first page by name", function()
            local route = bp.routes:insert({ name = "my-plugins-route", paths = { "/my-route" } })
            assert(db.plugins:insert {
              name = "key-auth",
              route = { id = route.id },
            })
            local res = assert(client:send {
              method = "GET",
              path = "/routes/my-plugins-route/plugins"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(1, #json.data)

            db.routes:delete({ id = route.id })
          end)

          it("ignores an invalid body", function()
            local route = bp.routes:insert({ paths = { "/my-route" } })
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

  describe("Admin API Override #" .. strategy, function()
    local bp
    local db
    local client

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
      }, {
        "api-override",
      })


      assert(helpers.start_kong({
        database      = strategy,
        plugins       = "bundled,api-override",
        nginx_conf    = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
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
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local res = client:post("/routes", {
              body = {
                protocols = { "http" },
                hosts     = { "my.route.com" },
                headers   = { location = { "my-location" } },
                service   = bp.services:insert(),
              },
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.same({ "my.route.com" }, json.hosts)
            assert.same({ location = { "my-location" } }, json.headers)
            assert.is_number(json.created_at)
            assert.is_number(json.regex_priority)
            assert.is_string(json.id)
            assert.equals(cjson.null, json.name)
            assert.equals(cjson.null, json.paths)
            assert.False(json.preserve_host)
            assert.True(json.strip_path)

            assert.equal("ok", res.headers["Kong-Api-Override"])
          end
        end)
      end)
      describe("GET", function()
        describe("with data", function()
          lazy_setup(function()
            db:truncate("services")
            db:truncate("routes")
            for i = 1, 10 do
              bp.routes:insert({ paths = { "/route-" .. i } })
            end
          end)

          it("retrieves the first page", function()
            local res = assert(client:send {
              method = "GET",
              path   = "/routes"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(10, #json.data)
            assert.equal("ok", res.headers["Kong-Api-Override"])

            local res = assert(client:send {
              method = "GET",
              path   = "/services"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(10, #json.data)
            assert.equal("ok", res.headers["Kong-Api-Override"])
          end)
        end)
      end)
    end)
  end)
end
