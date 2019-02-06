local cjson   = require "cjson"
local utils   = require "kong.tools.utils"
local helpers = require "spec.helpers"
local Errors  = require "kong.db.errors"


local unindent = helpers.unindent
local with_current_ws = helpers.with_current_ws


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
    local foo_ws

    setup(function()
      ngx.ctx.workspaces = nil
      bp, db, dao = helpers.get_db_utils(strategy)
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      helpers.stop_kong()
      assert(db:truncate())
      ngx.ctx.workspaces = nil
      assert(helpers.start_kong({
        database = strategy,
      }))

      client = assert(helpers.admin_client())

      local res = client:post("/workspaces", {
        body = {
          name = "foo",
        },
        headers = { ["Content-Type"] = "application/json" },
      })
      local body = assert.res_status(201, res)
      foo_ws = cjson.decode(body)
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("/foo/services", function()
      describe("POST", function()
        it_content_types("creates a service", function(content_type)
          return function()
            local res = client:post("/foo/services", {
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
      end)

      describe("GET", function()
        describe("with data", function()
          before_each(function()
            with_current_ws({ foo_ws }, function()
              for i = 1, 10 do
                assert(db.services:insert {
                  host = ("example%d.com"):format(i)
                })
              end
            end, dao)
          end)

          it("retrieves the first page", function()
            local res = client:get("/foo/services")
            local res = assert.res_status(200, res)
            local json = cjson.decode(res)
            assert.equal(10, #json.data)
          end)

          it("paginates a set", function()
            local pages = {}
            local offset

            for i = 1, 4 do
              local res = client:get("/foo/services",
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
      end)

      describe("/foo/services/{service}", function()
        local service

        before_each(function()
          with_current_ws({ foo_ws }, function ()
            service = bp.services:insert({ name = "my-service", protocol = "http", host="example.com", path="/path" })
          end, dao)
        end)

        describe("GET", function()
          it("should not with wrong workspace", function()
            local res  = client:get("/services/" .. service.id)
            assert.res_status(404, res)
          end)

          it("retrieves by id", function()
            local res  = client:get("/foo/services/" .. service.id)
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(service, json)
          end)

          it("retrieves by name", function()
            local res  = client:get("/foo/services/" .. service.name)
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(service, json)
          end)

          it("returns 404 if not found", function()
            local res = client:get("/foo/services/" .. utils.uuid())
            assert.res_status(404, res)
          end)

          it("returns 404 if not found by name", function()
            local res = client:get("/foo/services/not-found")
            assert.res_status(404, res)
          end)
        end)

        describe("PATCH", function()
          it_content_types("updates if found", function(content_type)
            return function()
              local res = client:patch("/foo/services/" .. service.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  name     = cjson.null,
                  protocol = "https",
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal(cjson.null, json.name)
              assert.equal("https",    json.protocol)
              assert.equal(service.id, json.id)

              with_current_ws({ foo_ws }, function ()
                local in_db = assert(db.services:select({ id = service.id }))
                assert.same(json, in_db)
              end, dao)
            end
          end)

          it_content_types("should not updates with wrong workspace", function(content_type)
            return function()
              local res = client:patch("/services/" .. service.id, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  protocol = "https",
                },
              })
              assert.res_status(404, res)
            end
          end)

          it_content_types("updates if found by name", function(content_type)
            return function()
              local res = client:patch("/foo/services/" .. service.name, {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  protocol = "https",
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("https",      json.protocol)
              assert.equal(service.id,   json.id)
              assert.equal(service.name, json.name)
              with_current_ws({ foo_ws }, function ()
                local in_db = assert(db.services:select_by_name(service.name))
                assert.same(json, in_db)
              end, dao)
            end
          end)
        end)

        describe("DELETE", function()
          it("should not delete a service with wrong workspace", function()
            local res  = client:delete("/services/" .. service.id)
            assert.res_status(204, res)
          end)

          it("deletes a service", function()
            local res  = client:get("/foo/services/" .. service.id)
            assert.res_status(200, res)


            local res  = client:delete("/foo/services/" .. service.id)
            local body = assert.res_status(204, res)
            assert.equal("", body)

            with_current_ws({ foo_ws }, function ()
              local in_db, err = db.services:select({ id = service.id })
              assert.is_nil(err)
              assert.is_nil(in_db)
            end, dao)
          end)

          it("deletes a service by name", function()
            local res  = client:delete("/foo/services/" .. service.name)
            local body = assert.res_status(204, res)
            assert.equal("", body)

            local in_db, err = db.services:select_by_name(service.name)
            assert.is_nil(err)
            assert.is_nil(in_db)
          end)

          describe("errors", function()
            it("returns HTTP 204 even if not found", function()
              local res = client:delete("/foo/services/" .. utils.uuid())
              assert.res_status(204, res)
            end)

            it("returns HTTP 204 even if not found by name", function()
              local res = client:delete("/foo/services/not-found")
              assert.res_status(204, res)
            end)
          end)
        end)

      end)

      describe("/foo/services/{service}/routes", function()
        it_content_types("lists all routes belonging to service", function(content_type)
          return function()
            local service, route
            with_current_ws({ foo_ws }, function()
              service = db.services:insert({
                protocol = "http",
                host     = "service.com",
              })

              route = db.routes:insert({
                protocol = "http",
                hosts    = { "service.com" },
                service  = service,
              })

              local _ = db.routes:insert({
                protocol = "http",
                hosts    = { "service.com" },
              })
            end, dao)

            local res = client:get("/foo/services/" .. service.id .. "/routes", {
              headers = { ["Content-Type"] = content_type },
            })

            local body = assert.res_status(200, res)
            local json = cjson.decode(body)

            assert.same({ data = { route }, next = cjson.null }, json)
          end
        end)
      end)

      describe("/foo/services/{service}/plugins", function()
        local service

        before_each(function()
          with_current_ws({ foo_ws }, function ()
            service = bp.services:insert {
              name     = "my-service",
              protocol = "http",
              host     = "my-service.com",
            }
          end, dao)
        end)

        describe("POST", function()
          it_content_types("creates a plugin config for a Service", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/foo/services/" .. service.id .. "/plugins",
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

          it_content_types("references a Service by name", function(content_type)
            return function()
              local res = assert(client:send {
                method = "POST",
                path = "/foo/services/" .. service.name .. "/plugins",
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
                  path = "/foo/services/" .. service.id .. "/plugins",
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
                  path = "/foo/services/" .. service.id .. "/plugins",
                  body = {
                    name = "basic-auth",
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                assert.response(res).has.status(201)
                assert.response(res).has.jsonbody()

                -- do it again, to provoke the error
                local res = assert(client:send {
                  method = "POST",
                  path = "/foo/services/" .. service.id .. "/plugins",
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
                  path = "/foo/services/" .. service.id .. "/plugins",
                  body = {
                    name = "basic-auth",
                  },
                  headers = { ["Content-Type"] = content_type }
                })
                local body = assert.res_status(201, res)
                local plugin = cjson.decode(body)

                -- do it again, to provoke the error
                local conflict_res = assert(client:send {
                  method = "POST",
                  path = "/foo/services/" .. service.id .. "/plugins",
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
                path = "/foo/services/" .. service.id .. "/plugins",
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
                path = "/foo/services/" .. service.id .. "/plugins",
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
                path = "/foo/services/" .. service.id .. "/plugins",
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
              local plugin
              with_current_ws({ foo_ws }, function ()
                plugin = assert(dao.plugins:insert {
                  name = "key-auth",
                  service_id = service.id,
                  config = { hide_credentials = true }
                })
                assert.True(plugin.config.hide_credentials)
                assert.same({ "apikey" }, plugin.config.key_names)
              end, dao)

              local res = assert(client:send {
                method = "PUT",
                path = "/foo/services/" .. service.id .. "/plugins",
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
              assert.same({ "apikey", "key" }, plugin.config.key_names)
            end
          end)

          it_content_types("overrides a plugin previous config if partial", function(content_type)
            return function()
              local plugin
              with_current_ws({ foo_ws }, function ()
                plugin = assert(dao.plugins:insert {
                  name = "key-auth",
                  service_id = service.id
                })
                assert.same({ "apikey" }, plugin.config.key_names)
              end, dao)

              local res = assert(client:send {
                method = "PUT",
                path = "/foo/services/" .. service.id .. "/plugins",
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
            local plugin
            return function()
              with_current_ws({ foo_ws }, function ()
                plugin = assert(dao.plugins:insert {
                  name = "key-auth",
                  service_id = service.id
                })
                assert.True(plugin.enabled)
              end, dao)

              local res = assert(client:send {
                method = "PUT",
                path = "/foo/services/" .. service.id .. "/plugins",
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
        end)

        describe("GET", function()
          it("retrieves the first page", function()
            with_current_ws({ foo_ws }, function ()
              assert(dao.plugins:insert {
                name = "key-auth",
                service_id = service.id
              })
            end, dao)
            local res = assert(client:send {
              method = "GET",
              path = "/foo/services/" .. service.id .. "/plugins"
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(1, #json.data)
          end)

          it("ignores an invalid body", function()
            local res = assert(client:send {
              method = "GET",
              path = "/foo/services/" .. service.id .. "/plugins",
              body = "this fails if decoded as json",
              headers = {
                ["Content-Type"] = "application/json",
              }
            })
            assert.res_status(200, res)
          end)
        end)
      end)

      describe("errors", function()
        it("handles malformed JSON body", function()
          local res = client:post("/foo/services", {
              body    = '{"hello": "world"',
              headers = { ["Content-Type"] = "application/json" }
            })
          local body = assert.res_status(400, res)
          assert.equal('{"message":"Cannot parse JSON body"}', body)
        end)

        it_content_types("handles invalid input", function(content_type)
          return function()
            -- Missing params
            local res = client:post("/foo/services", {
                body = {},
                headers = { ["Content-Type"] = content_type }
              })
            local body = assert.res_status(400, res)
            local json = cjson.decode(body)
            assert.same({
                host = "required field missing",
              }, json.fields)

            -- Invalid parameter
            res = client:post("/foo/services", {
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
            local res = client:post("/foo/services", {
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
    end)
  end)
end

