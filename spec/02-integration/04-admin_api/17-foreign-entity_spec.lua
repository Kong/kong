local helpers = require "spec.helpers"
local cjson = require "cjson"
local utils = require "kong.tools.utils"
local Errors = require "kong.db.errors"


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
    local client
    local db

    lazy_setup(function()
      local env = {}
      env.database = strategy
      env.plugins = env.plugins or "foreign-entity"

      local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
        [[./spec/fixtures/migrations/?/init.lua;]]..
        [[./spec/fixtures/custom_plugins/?.lua;]]..
        [[./spec/fixtures/custom_plugins/?/init.lua;" ]]

      local cmdline = "migrations up -c " .. helpers.test_conf_path
      local _, code, _, stderr = helpers.kong_exec(cmdline, env, true, lua_path)
      assert.same(0, code)
      assert.equal("", stderr)

      local _
      _, db = helpers.get_db_utils(strategy, {
        "foreign_entities",
        "foreign_references",
      }, {
        "foreign-entity",
      })

      assert(helpers.start_kong {
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "foreign-entity",
      })
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

    describe("/foreign-references/{foreign-reference}/same", function()
      describe("GET", function()
        it("retrieves by id", function()
          local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }, { nulls = true }))
          local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))

          local res  = client:get("/foreign-references/" .. foreign_reference.id .. "/same")
          local body = assert.res_status(200, res)

          local json = cjson.decode(body)
          assert.same(foreign_entity, json)

          assert(db.foreign_references:delete({ id = foreign_reference.id }))
          assert(db.foreign_entities:delete({ id = foreign_entity.id }))
        end)

        it("retrieves by name", function()
          local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }, { nulls = true }))
          local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))

          local res  = client:get("/foreign-references/foreign-reference/same")
          local body = assert.res_status(200, res)

          local json = cjson.decode(body)
          assert.same(foreign_entity, json)

          assert(db.foreign_references:delete({ id = foreign_reference.id }))
          assert(db.foreign_entities:delete({ id = foreign_entity.id }))
        end)

        it("returns 404 if not found", function()
          local res = client:get("/foreign-references/" .. utils.uuid() .. "/same")
          assert.res_status(404, res)
        end)

        it("returns 404 if not found by name", function()
          local res = client:get("/foreign-references/my-in-existent-foreign-reference/same")
          assert.res_status(404, res)
        end)

        it("ignores an invalid body", function()
          local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }, { nulls = true }))
          local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))

          local res = client:get("/foreign-references/" .. foreign_reference.id .. "/same", {
            headers = {
              ["Content-Type"] = "application/json"
            },
            body = "this fails if decoded as json",
          })
          assert.res_status(200, res)

          assert(db.foreign_references:delete({ id = foreign_reference.id }))
          assert(db.foreign_entities:delete({ id = foreign_entity.id }))
        end)
      end)

      describe("PATCH", function()
        it_content_types("updates if found", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }, { nulls = true }))
            local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))

            local edited_name = "name-" .. foreign_entity.name
            local res = client:patch("/foreign-references/" .. foreign_reference.id .. "/same", {
              headers = {
                ["Content-Type"] = content_type
              },
              body = {
                name  = edited_name,
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(edited_name, json.name)

            local in_db = assert(db.foreign_entities:select({ id = foreign_entity.id }, { nulls = true }))
            assert.same(json, in_db)

            assert(db.foreign_references:delete({ id = foreign_reference.id }))
            assert(db.foreign_entities:delete({ id = foreign_entity.id }))
          end
        end)

        it_content_types("updates if found by name", function(content_type)
          return function()
            if content_type == "multipart/form-data" then
              -- the client doesn't play well with this
              return
            end

            local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }, { nulls = true }))
            local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))
            local edited_name = "name-" .. foreign_entity.name
            local res = client:patch("/foreign-references/foreign-reference/same", {
              headers = {
                ["Content-Type"] = content_type
              },
              body = {
                name  = edited_name,
              },
            })
            local body = assert.res_status(200, res)
            local json = cjson.decode(body)
            assert.equal(edited_name, json.name)

            local in_db = assert(db.foreign_entities:select({ id = foreign_entity.id }, { nulls = true }))
            assert.same(json, in_db)

            assert(db.foreign_references:delete({ id = foreign_reference.id }))
            assert(db.foreign_entities:delete({ id = foreign_entity.id }))
          end
        end)

        describe("errors", function()
          it_content_types("returns 404 if not found", function(content_type)
            return function()
              local res = client:patch("/foreign-references/" .. utils.uuid() .. "/same", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  name  = "edited",
                },
              })
              assert.res_status(404, res)
            end
          end)

          it_content_types("handles invalid input", function(content_type)
            return function()
              local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }))
              local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))
              local res = client:patch("/foreign-references/" .. foreign_reference.id .. "/same", {
                headers = {
                  ["Content-Type"] = content_type
                },
                body = {
                  same = "foobar"
                },
              })
              local body = assert.res_status(400, res)
              assert.same({
                code    = Errors.codes.SCHEMA_VIOLATION,
                name    = "schema violation",
                message = "schema violation (same: expected a valid UUID)",
                fields  = {
                  same = "expected a valid UUID",
                },
              }, cjson.decode(body))

              assert(db.foreign_references:delete({ id = foreign_reference.id }))
              assert(db.foreign_entities:delete({ id = foreign_entity.id }))
            end
          end)
        end)
      end)

      describe("DELETE", function()
        describe("errors", function()
          it("returns HTTP 405 when trying to delete a foreign entity that is referenced", function()
            local foreign_entity = assert(db.foreign_entities:insert({ name = "foreign-entity" }))
            local foreign_reference = assert(db.foreign_references:insert({ name = "foreign-reference", same = foreign_entity }))
            local res  = client:delete("/foreign-references/" .. foreign_reference.id .. "/same")
            local body = assert.res_status(405, res)
            assert.same({ message = 'Method not allowed' }, cjson.decode(body))

            assert(db.foreign_references:delete({ id = foreign_reference.id }))
            assert(db.foreign_entities:delete({ id = foreign_entity.id }))
          end)

          it("returns HTTP 404 with non-existing foreign reference", function()
            local res = client:delete("/foreign-references/" .. utils.uuid() .. "/same")
            assert.res_status(404, res)
          end)

          it("returns HTTP 404 with non-existing foreign reference by name", function()
            local res = client:delete("/foreign-references/in-existent-route/same")
            assert.res_status(404, res)
          end)
        end)
      end)
    end)
  end)
end
