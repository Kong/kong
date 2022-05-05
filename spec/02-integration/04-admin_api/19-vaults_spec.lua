local helpers = require "spec.helpers"
local utils = require "kong.tools.utils"
local cjson = require "cjson"


local HEADERS = { ["Content-Type"] = "application/json" }


for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy, function()
    local client
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
        "vaults",
      })

      assert(helpers.start_kong({
        database = strategy,
        vaults = "bundled",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.admin_client()
    end)

    after_each(function()
      if client then
        client:close()
      end
    end)

    describe("/vaults", function()
      local vaults = {}

      lazy_setup(function()
        for i = 1, 3 do
          local res = helpers.admin_client():put("/vaults/env-" .. i, {
            headers = HEADERS,
            body = {
              name = "env",
            },
          })

          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          vaults[i] = json
        end
      end)

      describe("GET", function()
        it("retrieves all vaults configured", function()
          local res = client:get("/vaults")
          local body = assert.res_status(200, res)
          local json = cjson.decode(body)
          assert.equal(3, #json.data)
        end)
      end)

      it("returns 405 on invalid method", function()
        local methods = { "delete", "patch" }
        for i = 1, #methods do
          local res = client[methods[i]](client, "/vaults", {
            headers = HEADERS,
            body = {}, -- tmp: body to allow POST/PUT to work
          })
          local body = assert.response(res).has.status(405)
          local json = cjson.decode(body)
          assert.same({ message = "Method not allowed" }, json)
        end
      end)

      describe("/vaults/{vault}", function()
        describe("GET", function()
          it("retrieves a vault by id", function()
            local res = client:get("/vaults/" .. vaults[1].id)
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.same(vaults[1], json)
          end)

          -- TODO: `unique_across_ws=true` doesn't seem to work with Cassandra
          if strategy ~= "cassandra" then
            it("retrieves a vault by prefix", function()
              local res = client:get("/vaults/" .. vaults[1].prefix)
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.same(vaults[1], json)
            end)
          end

          it("returns 404 if not found by id", function()
            local res = client:get("/vaults/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c")
            assert.res_status(404, res)
          end)

          it("returns 404 if not found by prefix", function()
            local res = client:get("/vaults/not-found")
            assert.res_status(404, res)
          end)
        end)

        describe("PUT", function()
          it("can create a vault by id", function()
            local res = client:put("/vaults/" .. utils.uuid(), {
              headers = HEADERS,
              body = {
                name = "env",
                prefix = "put-env-id"
              },
            })
            assert.res_status(200, res)
          end)

          it("can create a vault by prefix", function()
            local res = client:put("/vaults/put-env-prefix", {
              headers = HEADERS,
              body = {
                name = "env",
              },
            })
            assert.res_status(200, res)
          end)

          describe("errors", function()
            it("handles invalid input by id", function()
              local res = client:put("/vaults/" .. utils.uuid(), {
                headers = HEADERS,
                body = {
                  name = "env",
                  prefix = "env",
                },
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({
                name = "schema violation",
                code = 2,
                message = "schema violation (prefix: must not be one of: env)",
                fields = {
                  prefix = "must not be one of: env",
                },
              }, json)
            end)

            -- TODO: `unique_across_ws=true` doesn't seem to work with Cassandra
            if strategy ~= "cassandra" then
              it("handles invalid input by prefix", function()
                local res = client:put("/vaults/env", {
                  headers = HEADERS,
                  body = {
                    name = "env",
                  },
                })
                local body = assert.res_status(400, res)
                local json = cjson.decode(body)
                assert.same({
                  name = "invalid unique prefix",
                  code = 10,
                  message = "must not be one of: env",
                }, json)
              end)
            end
          end)
        end)

        describe("PATCH", function()
          it("updates a vault by id", function()
            local res = client:patch("/vaults/" .. vaults[1].id, {
              headers = HEADERS,
              body = {
                config = {
                  prefix = "SSL_",
                }
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal("SSL_", json.config.prefix)

            vaults[1] = json
          end)

          -- TODO: `unique_across_ws=true` doesn't seem to work with Cassandra
          if strategy ~= "cassandra" then
            it("updates a vault by prefix", function()
              local res = client:patch("/vaults/env-1", {
                headers = HEADERS,
                body = {
                  config = {
                    prefix = "CERT_",
                  }
                },
              })
              local body = assert.res_status(200, res)
              local json = cjson.decode(body)
              assert.equal("CERT_", json.config.prefix)

              vaults[1] = json
            end)
          end

          describe("errors", function()
            it("handles invalid input by id", function()
              local res = client:patch("/vaults/" .. vaults[1].id, {
                headers = HEADERS,
                body = { prefix = "env" },
              })
              local body = assert.res_status(400, res)
              local json = cjson.decode(body)
              assert.same({
                name = "schema violation",
                code = 2,
                message = "schema violation (prefix: must not be one of: env)",
                fields = {
                  prefix = "must not be one of: env",
                },
              }, json)
            end)

            -- TODO: `unique_across_ws=true` doesn't seem to work with Cassandra
            if strategy ~= "cassandra" then
              it("handles invalid input by prefix", function()
                local res = client:patch("/vaults/env-1", {
                  headers = HEADERS,
                  body = { prefix = "env" },
                })
                local body = assert.res_status(400, res)
                local json = cjson.decode(body)
                assert.same({
                  name = "schema violation",
                  code = 2,
                  message = "schema violation (prefix: must not be one of: env)",
                  fields = {
                    prefix = "must not be one of: env",
                  },
                }, json)
              end)
            end

            it("returns 404 if not found", function()
              local res = client:patch("/vaults/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c", {
                headers = HEADERS,
                body = { prefix = "env" },
              })
              assert.res_status(404, res)
            end)
          end)
        end)

        describe("DELETE", function()
          it("deletes by id", function()
            local res = client:get("/vaults/" .. vaults[3].id)
            assert.res_status(200, res)

            res = client:delete("/vaults/" .. vaults[3].id)
            assert.res_status(204, res)

            res = client:get("/vaults/" .. vaults[3].id)
            assert.res_status(404, res)
          end)

          -- TODO: `unique_across_ws=true` doesn't seem to work with Cassandra
          if strategy ~= "cassandra" then
            it("deletes by prefix", function()
              local res = client:get("/vaults/env-2")
              assert.res_status(200, res)

              res = client:delete("/vaults/env-2")
              assert.res_status(204, res)

              res = client:get("/vaults/env-2")
              assert.res_status(404, res)
            end)
          end

          it("returns 204 if not found", function()
            local res = client:delete("/vaults/f4aecadc-05c7-11e6-8d41-1f3b3d5fa15c")
            assert.res_status(204, res)
          end)
        end)
      end)
    end)
  end)
end
