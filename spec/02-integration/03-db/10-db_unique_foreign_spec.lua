local Errors  = require "kong.db.errors"
local helpers = require "spec.helpers"
local utils   = require "kong.tools.utils"


local fmt = string.format


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local _, db
    local unique_foreigns
    local unique_references

    lazy_setup(function()
      _, db = helpers.get_db_utils(strategy, {
        "unique_foreigns",
        "unique_references",
      }, {
        "unique-foreign"
      })

      local env = {}
      env.database = strategy
      env.plugins = env.plugins or "unique-foreign"

      local lua_path = [[ KONG_LUA_PATH_OVERRIDE="./spec/fixtures/migrations/?.lua;]] ..
                       [[./spec/fixtures/migrations/?/init.lua;]]..
                       [[./spec/fixtures/custom_plugins/?.lua;]]..
                       [[./spec/fixtures/custom_plugins/?/init.lua;" ]]

      local cmdline = "migrations up -c " .. helpers.test_conf_path
      local _, code, _, stderr = helpers.kong_exec(cmdline, env, true, lua_path)
      assert.same(0, code)
      assert.equal("", stderr)

      unique_foreigns = {}
      unique_references = {}

      for i = 1, 5 do
        local unique_foreign = assert(db.unique_foreigns:insert({
          name = "unique_" .. i,
        }))

        local unique_reference = assert(db.unique_references:insert({
          note = "note_" .. i,
          unique_foreign = {
            id = unique_foreign.id
          }
        }))

        unique_foreigns[i] = unique_foreign
        unique_references[i] = unique_reference
      end
    end)

    describe("Unique Reference", function()
      describe(":select_by_unique_foreign()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.unique_references:select_by_unique_foreign(123)
          end, "unique_foreign must be a table")
        end)

        -- I/O
        it("returns existing Unique Foreign", function()
          for i = 1, 5 do
            local unique_reference, err, err_t = db.unique_references:select_by_unique_foreign({
              id = unique_foreigns[i].id,
            })

            assert.is_nil(err)
            assert.is_nil(err_t)

            assert.same(unique_references[i], unique_reference)
          end
        end)

        it("returns nothing on non-existing Unique Foreign", function()
          for i = 1, 5 do
            local unique_reference, err, err_t = db.unique_references:select_by_unique_foreign({
              id = utils.uuid()
            })

            assert.is_nil(err)
            assert.is_nil(err_t)
            assert.is_nil(unique_reference)
          end
        end)
      end)

      describe(":update_by_unique_foreign()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.unique_references:update_by_unique_foreign(123)
          end, "unique_foreign must be a table")
        end)

        it("errors on invalid values", function()
          local unique_reference, err, err_t = db.unique_references:update_by_unique_foreign({
            id = unique_foreigns[1].id,
          }, {
            note = 123,
          })
          assert.is_nil(unique_reference)
          local message = "schema violation (note: expected a string)"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = message,
            strategy    = strategy,
            fields      = {
              note  = "expected a string",
            }
          }, err_t)
        end)

        -- I/O
        it("returns not found error", function()
          local uuid = utils.uuid()
          local unique_reference, err, err_t = db.unique_references:update_by_unique_foreign({
            id = uuid,
          }, {
            note = "hello",
          })
          assert.is_nil(unique_reference)
          local message = fmt(
            [[[%s] could not find the entity with '{unique_foreign={id="%s"}}']],
            strategy, uuid)
          assert.equal(message, err)
          assert.equal(Errors.codes.NOT_FOUND, err_t.code)
        end)

        it("updates an existing Unique Reference", function()
          local unique_reference, err, err_t = db.unique_references:update_by_unique_foreign({
              id = unique_foreigns[1].id,
            }, {
            note = "note updated",
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("note updated", unique_reference.note)

          local unique_reference_in_db, err, err_t = db.unique_references:select({
            id = unique_reference.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("note updated", unique_reference_in_db.note)
        end)

        it("cannot update a Unique Reference to be an already existing Unique Foreign", function()
          local updated_service, _, err_t = db.unique_references:update_by_unique_foreign({
            id = unique_foreigns[1].id,
          }, {
            unique_foreign = {
              id = unique_foreigns[2].id,
            }
          })
          assert.is_nil(updated_service)
          assert.same({
            code     = Errors.codes.UNIQUE_VIOLATION,
            name     = "unique constraint violation",
            message  = fmt([[UNIQUE violation detected on '{unique_foreign={id="%s"}}']], unique_foreigns[2].id),
            strategy = strategy,
            fields   = {
              unique_foreign = {
                id = unique_foreigns[2].id,
              }
            }
          }, err_t)
        end)
      end)

      describe(":upsert_by_unique_foreign()", function()
        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.unique_references:upsert_by_unique_foreign(123)
          end, "unique_foreign must be a table")
        end)

        it("errors on invalid values", function()
          local unique_reference, err, err_t = db.unique_references:upsert_by_unique_foreign({
            id = unique_foreigns[1].id,
          }, {
            note = 123,
          })
          assert.is_nil(unique_reference)
          local message = "schema violation (note: expected a string)"
          assert.equal(fmt("[%s] %s", strategy, message), err)
          assert.same({
            code        = Errors.codes.SCHEMA_VIOLATION,
            name        = "schema violation",
            message     = message,
            strategy    = strategy,
            fields      = {
              note  = "expected a string",
            }
          }, err_t)
        end)

        -- I/O
        it("returns not found error", function()
          local uuid = utils.uuid()
          local unique_reference, err, err_t = db.unique_references:upsert_by_unique_foreign({
            id = uuid,
          }, {
            note = "hello",
          })
          assert.is_nil(unique_reference)
          local message = fmt(
            [[[%s] the foreign key '{id="%s"}' does not reference an existing 'unique_foreigns' entity.]],
            strategy, uuid)
          assert.equal(message, err)
          assert.equal(Errors.codes.FOREIGN_KEY_VIOLATION, err_t.code)
        end)

        it("upserts an existing Unique Reference", function()
          local unique_reference, err, err_t = db.unique_references:upsert_by_unique_foreign({
            id = unique_foreigns[1].id,
          }, {
            note = "note updated",
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("note updated", unique_reference.note)

          local unique_reference_in_db, err, err_t = db.unique_references:select({
            id = unique_reference.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("note updated", unique_reference_in_db.note)
        end)

        it("unique foreign given with entity is ignored when upserting by unique foreign", function()
          -- TODO: this is slightly unexpected, but it has its uses when thinking about idempotency
          --       of `PUT`. This has been like that with other DAO methods do, but perhaps we want
          --       to revisit this later.
          local unique_reference, err, err_t = db.unique_references:upsert_by_unique_foreign({
            id = unique_foreigns[1].id,
          }, {
            unique_foreign = {
              id = unique_foreigns[2].id,
            }
          })

          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal(unique_foreigns[1].id, unique_reference.unique_foreign.id)
        end)
      end)

      describe(":update()", function()
        it("cannot update a Unique Reference to be an already existing Unique Foreign", function()
          local updated_unique_reference, _, err_t = db.unique_references:update({
            id = unique_references[1].id,
          }, {
            unique_foreign = {
              id = unique_foreigns[2].id,
            }
          })

          assert.is_nil(updated_unique_reference)
          assert.same({
            code     = Errors.codes.UNIQUE_VIOLATION,
            name     = "unique constraint violation",
            message  = fmt([[UNIQUE violation detected on '{unique_foreign={id="%s"}}']], unique_foreigns[2].id),
            strategy = strategy,
            fields   = {
              unique_foreign = {
                id = unique_foreigns[2].id,
              }
            }
          }, err_t)
        end)

        it("changes a Unique Reference to point to a new Unique Foreign", function()
          local unique_foreign = assert(db.unique_foreigns:insert({
            name = "new unique foreign",
          }))

          local updated_unique_reference, err, err_t = db.unique_references:update({
            id = unique_references[1].id,
          }, {
            note = "updated note",
            unique_foreign = {
              id = unique_foreign.id,
            },
          })

          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.equal("updated note", updated_unique_reference.note)
          assert.equal(unique_foreign.id, updated_unique_reference.unique_foreign.id)
        end)
      end)

      describe(":delete_by_unique_foreign()", function()
        local unique_foreign
        local unique_reference

        lazy_setup(function()
          unique_foreign = assert(db.unique_foreigns:insert({
            name = "test",
          }))

          unique_reference = assert(db.unique_references:insert({
            note = "test",
            unique_foreign = {
              id = unique_foreign.id
            }
          }))
        end)

        -- no I/O
        it("errors on invalid arg", function()
          assert.has_error(function()
            db.unique_references:delete_by_unique_foreign(123)
          end, "unique_foreign must be a table")
        end)

        -- I/O
        it("returns nothing if the Unique Foreign does not exist", function()
          local ok, err, err_t = db.unique_references:delete_by_unique_foreign({
            id = utils.uuid()
          })
          assert.is_true(ok)
          assert.is_nil(err_t)
          assert.is_nil(err)
        end)

        it("deletes an existing Unique Reference", function()
          local ok, err, err_t = db.unique_references:delete_by_unique_foreign({
            id = unique_foreign.id,
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_true(ok)

          local unique_reference, err, err_t = db.unique_references:select({
            id = unique_reference.id
          })
          assert.is_nil(err_t)
          assert.is_nil(err)
          assert.is_nil(unique_reference)
        end)
      end)
    end)

  end) -- kong.db [strategy]
end
