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
    local _
    local client
    local foo_ws

    setup(function()
      bp, db, _ = helpers.get_db_utils(strategy)

      assert(helpers.start_kong({
        database = strategy,
      }))

      foo_ws = assert(bp.workspaces:insert {
        name = "foo",
      })

      client = assert(helpers.admin_client())
    end)

    teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      if client then
        client:close()
      end

      client = assert(helpers.admin_client())

      -- XXX truncate workspace_entities behind the scenes? maybe have a
      -- spec helper to do so?
      db:truncate("workspace_entities")
      db:truncate("services")
      db:truncate("routes")
      db:truncate("plugins")
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
          end
        end)
      end)

      describe("GET", function()
        describe("with data", function()
          before_each(function()
            for i = 1, 10 do
              assert(bp.services:insert_ws({
                host = ("example%d.com"):format(i)
              }, foo_ws))
            end
          end)

          it("retrieves the first page", function()
            local res = client:get("/foo/services")
            local res = assert.res_status(200, res)
            local json = cjson.decode(res)
            assert.equal(10, #json.data)
          end)

          it("paginates a set", function()
            local offset
            local pages = {}
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
    end)

    describe("/foo/services/{service}", function()
      local service

      before_each(function()
        service = bp.services:insert_ws({
          name = "my-service",
          protocol = "http",
          host = "example.com",
        }, foo_ws)
      end)

      describe("GET", function()
        it("doesn't retrieve from the wrong workspace", function()
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
                name     = "example-2",
                protocol = "https",
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("https",    json.protocol)
            assert.equal(service.id, json.id)

            with_current_ws({ foo_ws }, function ()
              local in_db = assert(db.services:select({ id = service.id }))
              json.path = nil
              assert.same(json, in_db)
            end, db)
          end
        end)

        it_content_types("should not update with wrong workspace", function(content_type)
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
              json.path = nil
              assert.same(json, in_db)
            end, db)
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
          end, db)
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

          service = assert(bp.services:insert_ws({
            host     = "service.com",
          }, foo_ws))

          route = assert(bp.routes:insert_ws({
            hosts    = { "service.com" },
            service  = service,
          }, foo_ws))

          -- add explicit null values to entity queried directly from db
          -- (while the admin returns entities with explicit nulls, the db
          -- does not)
          route = db.routes.schema:process_auto_fields(route, "select", true)

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
        service = bp.services:insert_ws({
          name = "my-service",
          protocol = "http",
          host = "example.com",
        }, foo_ws)
      end)

      describe("POST", function()
        local inputs = {
          ["application/x-www-form-urlencoded"] = {
            name = "key-auth",
            ["config.key_names[1]"] = "apikey",
            ["config.key_names[2]"] = "key",
          },
          ["application/json"] = {
            name = "key-auth",
            config = {
              key_names = {"apikey", "key"}
            },
          },
        }

        it_content_types("creates a plugin config for a Service", function(content_type)
          return function()
            local res = assert(client:send {
              method = "POST",
              path = "/foo/services/" .. service.id .. "/plugins",
              body = inputs[content_type],
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
              body = inputs[content_type],
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
              assert.same("schema violation", json.name)
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
              assert.same("unique constraint violation", json.name)
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
              local conflict_body = assert.res_status(400, conflict_res)
              local json = cjson.decode(conflict_body)
              assert.same("primary key violation", json.name)
            end
          end)
        end)
      end)

      describe("PUT", function()
        local inputs = {
          ["application/x-www-form-urlencoded"] = {
            name = "key-auth",
            ["config.key_names[1]"] = "apikey",
            ["config.key_names[2]"] = "key",
            created_at = 1461276890000
          },
          ["application/json"] = {
            name = "key-auth",
            config = {
              key_names = {"apikey", "key"}
            },
            created_at = 1461276890000
          },
        }

        -- XXX pending on a core fix
        -- https://github.com/Kong/kong/commit/6c1fb394c69521bfdbd65ea04f338555f6d3691d
        -- [[

        it_content_types("#flaky creates if not exists", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. utils.uuid(),
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)
            assert.equal("key-auth", json.name)
            assert.same({ "apikey", "key" }, json.config.key_names)
          end
        end)

        it_content_types("#flaky replaces if exists", function(content_type)
          return function()
            local res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. utils.uuid(),
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(201, res)
            local json = cjson.decode(body)

            res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. json.id,
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            body = assert.res_status(200, res)
            json = cjson.decode(body)
            assert.equal("key-auth", json.name)
            assert.same({ "key" }, json.config.key_names)
          end
        end)

        -- ]]

        it_content_types("uses default values when replacing", function(content_type)
          return function()
            local plugin = assert(bp.plugins:insert_ws({
              name = "key-auth",
              service = {
                id = service.id,
              },
              config = { hide_credentials = true }
            }, foo_ws))
            assert.True(plugin.config.hide_credentials)
            assert.same({ "apikey" }, plugin.config.key_names)

            local res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. plugin.id,
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.config.hide_credentials) -- not true anymore

            with_current_ws({foo_ws}, function()
              plugin = assert(db.plugins:select {
                id = plugin.id,
              })
            end)

            assert.False(plugin.config.hide_credentials)
            assert.same({ "apikey", "key" }, plugin.config.key_names)
          end
        end)

        it_content_types("overrides a plugin previous config if partial", function(content_type)
          return function()
            local plugin = assert(bp.plugins:insert_ws({
              name = "key-auth",
              service = {
                id = service.id,
              },
            }, foo_ws))
            assert.same({ "apikey" }, plugin.config.key_names)

            local res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. plugin.id,
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same({ "apikey", "key" }, json.config.key_names)
          end
        end)

        it_content_types("updates the `enabled` property", function(content_type)
          return function()
            local plugin = assert(bp.plugins:insert_ws({
              name = "key-auth",
              service = {
                id = service.id,
              },
            }, foo_ws))
            assert.True(plugin.enabled)

            inputs[content_type].enabled = false

            local res = assert(client:send {
              method = "PUT",
              path = "/foo/services/" .. service.id .. "/plugins/" .. plugin.id,
              body = inputs[content_type],
              headers = { ["Content-Type"] = content_type }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            with_current_ws({foo_ws}, function()
              plugin = assert(db.plugins:select {
                id = plugin.id,
              })
            end)
            assert.False(plugin.enabled)
          end
        end)
      end)

      describe("GET", function()
        it("retrieves the first page", function()
          assert(bp.plugins:insert_ws({
            name = "key-auth",
            service = {
              id = service.id,
            },
          }, foo_ws))

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

    describe("#o errors", function()
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
          assert.same({ protocol = "expected one of: http, https, tcp, tls" }, json.fields)
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
end
