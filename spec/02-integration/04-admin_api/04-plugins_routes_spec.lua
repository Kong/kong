local helpers = require "spec.helpers"
local admin_api = require "spec.fixtures.admin_api"
local uuid = require "kong.tools.uuid"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy() do

  describe("Admin API #" .. strategy, function()
    local db
    local client

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "services",
        "routes",
        "plugins",
      }, {
        "key-auth"
      })

      assert(helpers.start_kong({
        database = strategy,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("/plugins/enabled", function()
      it("returns a list of enabled plugins on this node", function()
        local res = assert(client:send {
          method = "GET",
          path = "/plugins/enabled",
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.is_table(json.enabled_plugins)
        assert.True(#json.enabled_plugins > 0)
      end)
    end)

    describe("/plugins", function()
      local services = {}
      local plugins = {}

      lazy_setup(function()
        for i = 1, 3 do
          local service, err, err_t = db.services:insert {
            name = "service-" .. i,
            protocol = "http",
            host = "127.0.0.1",
            port = 15555,
          }
          assert.is_nil(err_t)
          assert.is_nil(err)

          db.routes:insert({
            service = { id = service.id },
            hosts = { "route_" .. tostring(i) .. ".test" }
          })

          services[i] = service

          plugins[i] = assert(db.plugins:insert({
            name = "key-auth",
            instance_name = "key-auth-" .. i,
            service = { id = service.id },
            config = {
              key_names = { "testkey" },
            }
          }, { nulls = true }))
        end

        local service, err, err_t = db.services:insert {
          name = "service-4",
          protocol = "http",
          host = "127.0.0.1",
          port = 15555,
        }
        assert.is_nil(err_t)
        assert.is_nil(err)
        services[4] = service
        plugins[4] = assert(db.plugins:insert({
          name = "key-auth",
          instance_name = "円", -- utf-8
          service = { id = service.id },
          config = {
            key_names = { "testkey" },
          }
        }, { nulls = true }))
      end)

      describe("GET", function()
        it("retrieves all plugins configured", function()
          local res = assert(client:send {
            method = "GET",
            path = "/plugins"
          })
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(4, #json.data)
        end)
      end)
      it("returns 405 on invalid method", function()
        local methods = {"DELETE", "PATCH"}
        for i = 1, #methods do
          local res = assert(client:send {
            method = methods[i],
            path = "/plugins",
            body = {}, -- tmp: body to allow POST/PUT to work
            headers = {["Content-Type"] = "application/json"}
          })
          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("/plugins/{plugin}", function()
        describe("GET", function()
          it("retrieves a plugin by id", function()
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/" .. plugins[1].id
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(plugins[1], json)
          end)
          it("retrieves a plugin by instance_name", function()
            print("/plugins/" .. plugins[1].instance_name)
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/" .. plugins[1].instance_name
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(plugins[1], json)
          end)
          it("returns 404 if not found", function()
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c"
            })
            assert.res_status(404, res)
          end)
          it("returns 404 if not found by instance_name", function()
            local res = assert(client:send {
              method = "GET",
              path = "/plugins/not-found"
            })
            assert.res_status(404, res)
          end)
          it("retrieves by utf-8 name and percent-escaped utf-8 name", function()
            local res  = client:get("/plugins/" .. plugins[4].instance_name)
            local body = assert.res_status(200, res)

            local json = cjson.decode(body)
            assert.same(plugins[4], json)

            res  = client:get("/plugins/%E5%86%86")
            body = assert.res_status(200, res)

            json = cjson.decode(body)
            assert.same(plugins[4], json)
          end)
        end)


        describe("PUT", function()
          it("can create a plugin", function()
            local service = admin_api.services:insert()
            admin_api.routes:insert({
              paths = { "/mypath" },
              service = { id = service.id },
            })
            local res = assert(client:send {
              method = "PUT",
              path = "/plugins/" .. uuid.uuid(),
              body = {
                name = "key-auth",
                service = {
                  id = service.id,
                }
              },
              headers = {["Content-Type"] = "application/json"}
            })
            assert.res_status(200, res)
          end)

          it("can create a plugin by instance_name", function()
            local service = admin_api.services:insert()
            local instance_name = "name-" .. uuid.uuid()
            local res = assert(client:send {
              method = "PUT",
              path = "/plugins/" .. instance_name,
              body = {
                name = "key-auth",
                service = {
                  id = service.id,
                }
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(instance_name, json.instance_name)
          end)

          it("can upsert a plugin by instance_name", function()
            -- create a plugin by instance_name
            local service = admin_api.services:insert()
            local instance_name = "name-" .. uuid.uuid()
            local plugin_id
            local res = assert(client:send {
              method = "PUT",
              path = "/plugins/" .. instance_name,
              body = {
                name = "key-auth",
                service = {
                  id = service.id,
                },
                config = {
                  key_names = { "testkey" },
                }
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(200, res)
            plugin_id = cjson.decode(body).id

            -- update a plugin by instance_name
            local res2 = assert(client:send {
              method = "PUT",
              path = "/plugins/" .. instance_name,
              body = {
                name = "key-auth",
                service = {
                  id = service.id,
                },
                config = {
                  key_names = { "testkey2" },
                }
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(200, res2)
            local json = cjson.decode(body)
            -- upsert operation should not change the plugin id
            assert(plugin_id, json.id)
            assert("testkey2", json.config.key_names[1])
          end)
        end)


        describe("PATCH", function()
          it("updates a plugin", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugins[1].id,
              body = {enabled = false},
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            local in_db = assert(db.plugins:select(plugins[1], { nulls = true }))
            assert.same(json, in_db)
          end)
          it("updates a plugin by instance_name", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugins[2].instance_name,
              body = { enabled = false },
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.False(json.enabled)

            local in_db = assert(db.plugins:select(plugins[2], { nulls = true }))
            assert.same(json, in_db)
          end)
          it("updates a plugin bis", function()
            local plugin = assert(db.plugins:select(plugins[2], { nulls = true }))

            plugin.enabled = not plugin.enabled
            plugin.created_at = nil
            plugin.updated_at = nil

            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugin.id,
              body = plugin,
              headers = {["Content-Type"] = "application/json"}
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(plugin.enabled, json.enabled)
          end)
          it("updates a plugin (removing foreign key reference)", function()
            assert.equal(services[2].id, plugins[2].service.id)

            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugins[2].id,
              body = {
                service = cjson.null,
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(ngx.null, json.service)

            local in_db = assert(db.plugins:select(plugins[2], { nulls = true }))
            assert.same(json, in_db)
          end)
          it("does not infer json input", function()
            local res = assert(client:send {
              method = "PATCH",
              path = "/plugins/" .. plugins[2].id,
              body = {
                tags = cjson.null,
              },
              headers = { ["Content-Type"] = "application/json" }
            })
            assert.res_status(200, res)
          end)
          describe("errors", function()
            it("handles invalid input", function()
              local before = assert(db.plugins:select(plugins[1], { nulls = true }))
              local res = assert(client:send {
                method = "PATCH",
                path = "/plugins/" .. plugins[1].id,
                body = { foo = "bar" },
                headers = {["Content-Type"] = "application/json"}
              })
              local body = cjson.decode(assert.res_status(400, res))
              assert.same({
                message = "schema violation (foo: unknown field)",
                name = "schema violation",
                fields = {
                  foo = "unknown field",
                },
                code = 2,
              }, body)

              local after = assert(db.plugins:select(plugins[1], { nulls = true }))
              assert.same(before, after)
              assert.same({"testkey"}, after.config.key_names)
            end)
            it("handles invalid config, see #9224", function()
              local before = assert(db.plugins:select(plugins[1], { nulls = true }))
              local res = assert(client:send {
                method = "PATCH",
                path = "/plugins/" .. plugins[1].id,
                body = { config = "bar" },
                headers = {["Content-Type"] = "application/json"}
              })
              local body = cjson.decode(assert.res_status(400, res))
              assert.same({
                message = "schema violation (config: expected a record)",
                name = "schema violation",
                fields = {
                  config = "expected a record",
                },
                code = 2,
              }, body)

              local after = assert(db.plugins:select(plugins[1], { nulls = true }))
              assert.same(before, after)
              assert.same({"testkey"}, after.config.key_names)
            end)

            it("returns 404 if not found", function()
              local res = assert(client:send {
                method = "PATCH",
                path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c",
                body = {enabled = false},
                headers = {["Content-Type"] = "application/json"}
              })
              assert.res_status(404, res)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes by id", function()
            local res = assert(client:send {
              method = "DELETE",
              path = "/plugins/" .. plugins[3].id
            })
            assert.res_status(204, res)
          end)
          it("deletes by instance_name", function()
            local res = client:delete("/plugins/" .. plugins[4].instance_name)
            local body = assert.res_status(204, res)
            assert.equal("", body)

            local res = client:get("/plugins/" .. plugins[4].instance_name)
            assert.res_status(404, res)
          end)
          describe("errors", function()
            it("returns 204 if not found", function()
              local res = assert(client:send {
                method = "DELETE",
                path = "/plugins/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c"
              })
              assert.res_status(204, res)
            end)

            it("returns 204 if not found by instance_name", function()
              local res = client:delete("/plugins/not-found")
              assert.res_status(204, res)
            end)
          end)
        end)
      end)
    end)

    describe("/schemas/plugins/{plugin}", function()
      describe("GET", function()
        it("returns the schema of all bundled plugins", function()
          for plugin, _ in pairs(helpers.test_conf.loaded_plugins) do
            local res = assert(client:send {
              method = "GET",
              path = "/schemas/plugins/" .. plugin,
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.is_table(json.fields)
            assert.is_table(json.entity_checks)
          end
        end)
        it("returns nested records and empty array defaults as arrays", function()
          local res = assert(client:send {
            method = "GET",
            path = "/schemas/plugins/request-transformer",
          })
          local body = assert.res_status(200, res)
          assert.not_match('"entity_checks":{', body, 1, true)
          assert.not_match('"fields":{', body, 1, true)
          assert.match('"default":[]', body, 1, true)
          assert.not_match('"default":{}', body, 1, true)
        end)

        it("returns 404 on invalid plugin", function()
          local res = assert(client:send {
            method = "GET",
            path = "/schemas/plugins/foobar",
          })
          local body = assert.res_status(404, res)
          local json = cjson.decode(body)
          assert.same({ message = "No plugin named 'foobar'" }, json)
        end)
      end)
    end)
  end)

end
