local workspaces = require "kong.workspaces"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local bp, db

    lazy_setup(function()
      bp, db, _ = helpers.get_db_utils(strategy)

      local s1
      s1 = bp.services:insert({ name = "s1" })
      bp.services:insert({ name = "s2" })
      bp.services:insert({ name = "s3" })

      bp.routes:insert({ name = "r1", paths = {"/"}, service = s1 })
      bp.routes:insert({ name = "r2", paths = {"/"}, service = s1 })
      bp.routes:insert({ name = "r3", paths = {"/"}, service = s1 })

      bp.consumers:insert({ username = "c1" })
      bp.consumers:insert({ username = "c2" })
      bp.consumers:insert({ username = "c3" })
    end)

    describe(":select_all()", function()
      describe("returns all rows", function()
        it("partitioned entities", function()
          local rows, err

          rows, err = db.services:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)

          rows, err = db.routes:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)
        end)

        it("partitioned entities", function()
          local rows, err = db.consumers:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)
        end)
      end)

      describe("filters", function()
        it("partitioned entities", function()
          local rows, err

          rows, err = db.services:select_all({ name = "s1" })
          assert.is_nil(err)
          assert.same(1, #rows)

          rows, err = db.routes:select_all({ name = "r1" })
          assert.is_nil(err)
          assert.same(1, #rows)
        end)

        it("unpartitioned entities", function()
          local rows, err

          rows, err = db.consumers:select_all({ username = "c1" })
          assert.is_nil(err)
          assert.same(1, #rows)
        end)

        it("resolves shared entities", function()
          local ws_d = assert(db.workspaces:select_by_name("default"))
          local ws_1 = assert(bp.workspaces:insert({
            name = "w1"
          }))
          local c1 = assert(bp.consumers:insert_ws({
            username = "c123",
          }, ws_d))

          assert.is_nil(workspaces.add_entity_relation("consumers", c1, ws_1))

          assert.same({c1}, workspaces.run_with_ws_scope({ws_1}, function()
            return db.consumers:select_all({
              username = "c123"
            })
          end))
        end)
      end)

      describe("errors", function()
        it("on inexistent columns", function()
          local err

          _, err = db.services:select_all({ foo = "bar" })
          assert.matches("foo: unknown field", err)
        end)

        it("with wrong value types", function()
          local err

          _, err = db.services:select_all({ name = 1 })
          assert.matches("name: expected a string", err)
        end)
      end)
    end)
  end)
end
