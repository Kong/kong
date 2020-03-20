local workspaces = require "kong.workspaces"
local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local bp, db

    lazy_setup(function()
      bp, db, _ = helpers.get_db_utils(strategy)
    end)

    before_each(function()
      db:truncate("routes")
      db:truncate("services")
      db:truncate("consumers")
      db:truncate("workspaces")
    end)

    describe(":select_all()", function()
      describe("returns all rows", function()
        it("partitioned entities", function()
          local rows, err

          local s1
          s1 = bp.services:insert({ name = "s1" })
          bp.services:insert({ name = "s2" })
          bp.services:insert({ name = "s3" })

          bp.routes:insert({ name = "r1", paths = {"/"}, service = s1 })
          bp.routes:insert({ name = "r2", paths = {"/"}, service = s1 })
          bp.routes:insert({ name = "r3", paths = {"/"}, service = s1 })

          rows, err = db.services:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)

          rows, err = db.routes:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)
        end)

        it("unpartitioned entities", function()
          bp.consumers:insert({ username = "c1" })
          bp.consumers:insert({ username = "c2" })
          bp.consumers:insert({ username = "c3" })

          local rows, err = db.consumers:select_all()
          assert.is_nil(err)
          assert.same(3, #rows)
        end)

        it("in a given workspace", function()
          local ws1 = assert(bp.workspaces:insert({ name = "ws_90" }))

          assert(bp.services:insert_ws({ name = "c90", host = "c90.com" }, ws1))
          assert(bp.services:insert_ws({ name = "c91", host = "c91.com" }, ws1))

          local rows, err = workspaces.run_with_ws_scope({ws1}, function()
            return db.services:select_all()
          end)

          assert.is_nil(err)
          assert.same(2, #rows)
        end)

        it("in all workspaces", function()
          local ws1 = assert(bp.workspaces:insert({ name = "ws_91" }))
          local ws2 = assert(bp.workspaces:insert({ name = "ws_92" }))
          local ws3 = assert(bp.workspaces:insert({ name = "ws_93" }))

          assert(bp.services:insert_ws({ name = "c90", host = "c90.com" }, ws1))
          assert(bp.services:insert_ws({ name = "c91", host = "c91.com" }, ws2))
          assert(bp.services:insert_ws({ name = "c91", host = "c91.com" }, ws3))

          local rows, err = workspaces.run_with_ws_scope({}, function()
            return db.services:select_all()
          end)

          assert.is_nil(err)
          assert.same(3, #rows)
        end)
      end)

      describe("filters", function()
        it("partitioned entities", function()
          local rows, err

          local s1 = bp.services:insert({ name = "s1" })
          bp.routes:insert({ name = "r1", paths = {"/"}, service = s1 })

          rows, err = db.services:select_all({ name = "s1" })
          assert.is_nil(err)
          assert.same(1, #rows)

          rows, err = db.routes:select_all({ name = "r1" })
          assert.is_nil(err)
          assert.same(1, #rows)
        end)

        it("unpartitioned entities", function()
          local rows, err
          bp.services:insert({ name = "c1", host = "c1.com" })

          rows, err = db.services:select_all({ name = "c1" })
          assert.is_nil(err)
          assert.same(1, #rows)
        end)

        it("non-workspaceable entities", function()
          local ws1 = assert(bp.workspaces:insert({ name = "ws_24" }))

          assert(bp.services:insert_ws({ name = "ws1", host = "ws1.com" }, ws1))
          assert(bp.services:insert_ws({ name = "ws2", host = "ws2.com" }, ws1))

          -- workspace_entities is NOT workspace-aware
          local res, err

          res, err = db.workspace_entities:select_all()
          assert.is_nil(err)
          assert.truthy(#res > 0)

          res, err = db.workspace_entities:select_all({
            workspace_id = ws1.id,
          })
          assert.is_nil(err)
          assert.same(#res, 4)
        end)

        it("filters out other workspaces' entities (developers)", function()
          local s = require "kong.singletons"
          s.configuration = { portal_auth = "basic-auth" }

          local ws1 = assert(bp.workspaces:insert({ name = "ws_11" }))
          local ws2 = assert(bp.workspaces:insert({ name = "ws_22" }))

          local c1 = assert(bp.developers:insert_ws({
            email = "developer1@example.com",
            meta = '{"full_name":"Test Name"}',
            password = "test",
          }, ws1))

          local c2 = assert(bp.developers:insert_ws({
            email = "developer2@example.com",
            meta = '{"full_name":"Test Name"}' ,
            password = "test",
          }, ws1))

          local c3 = assert(bp.developers:insert_ws({
            email = "developer3@example.com",
            meta = '{"full_name":"Test Name"}',
            password = "test",
          }, ws1))

          local c4 = assert(bp.developers:insert_ws({
            email = "developer4@example.com",
            meta = '{"full_name":"Test Name"}',
            password = "test",
          }, ws2))

          local c5 = assert(bp.developers:insert_ws({
            email = "developer5@example.com",
            meta = '{"full_name":"Test Name"}',
            password = "test",
          }, ws2))

          local c6 = assert(bp.developers:insert_ws({
            email = "developer6@example.com",
            meta = '{"full_name":"Test Name"}',
            password = "test",
          }, ws2))

          local sort = function(a, b)
            return a.email < b.email
          end

          local res

          res = workspaces.run_with_ws_scope({ws1}, function()
            return db.developers:select_all()
          end)
          table.sort(res, sort)
          assert.same({c1, c2, c3}, res)

          res = workspaces.run_with_ws_scope({ws2}, function()
            return db.developers:select_all()
          end)
          table.sort(res, sort)
          assert.same({c4, c5, c6}, res)
        end)

        it("filters out other workspaces' entities (services)", function()
          local ws1 = assert(bp.workspaces:insert({ name = "ws_12" }))
          local ws2 = assert(bp.workspaces:insert({ name = "ws_23" }))

          local c1 = assert(bp.services:insert_ws({ name = "ws1", host = "ws1.com" }, ws1))
          local c2 = assert(bp.services:insert_ws({ name = "ws2", host = "ws2.com" }, ws1))
          local c3 = assert(bp.services:insert_ws({ name = "ws3", host = "ws3.com" }, ws1))

          local c4 = assert(bp.services:insert_ws({ name = "ws4", host = "ws4.com" }, ws2))
          local c5 = assert(bp.services:insert_ws({ name = "ws5", host = "ws5.com" }, ws2))
          local c6 = assert(bp.services:insert_ws({ name = "ws6", host = "ws6.com" }, ws2))

          local sort = function(a, b)
            return a.name < b.name
          end

          local res

          res = workspaces.run_with_ws_scope({ws1}, function()
            return db.services:select_all()
          end)
          table.sort(res, sort)
          assert.same({c1, c2, c3}, res)

          res = workspaces.run_with_ws_scope({ws2}, function()
            return db.services:select_all()
          end)
          table.sort(res, sort)
          assert.same({c4, c5, c6}, res)
        end)

        it("resolves shared entities", function()
          local ws_d = assert(db.workspaces:select_by_name("default"))
          local ws_1 = assert(bp.workspaces:insert({
            name = "w1"
          }))
          local c1 = assert(bp.services:insert_ws({
            name = "c123",
            host = "c123.com",
          }, ws_d))

          assert.is_nil(workspaces.add_entity_relation("services", c1, ws_1))

          assert.same({c1}, workspaces.run_with_ws_scope({ws_1}, function()
            return db.services:select_all({
              name = "c123"
            })
          end))
        end)

        it("resolves entities with same unique keys in different workspaces", function()
          local ws_1 = assert(bp.workspaces:insert({ name = "ws_1" }))
          local ws_2 = assert(bp.workspaces:insert({ name = "ws_2" }))

          local c1_ws1 = assert(bp.services:insert_ws({ name = "ws1", host = "ws1.com" }, ws_1))
          local c1_ws2 = assert(bp.services:insert_ws({ name = "ws1", host = "ws1.com" }, ws_2))

          assert.same({c1_ws1}, workspaces.run_with_ws_scope({ws_1}, function()
            return db.services:select_all({
              name = "ws1"
            })
          end))

          assert.same({c1_ws2}, workspaces.run_with_ws_scope({ws_2}, function()
            return db.services:select_all({
              name = "ws1"
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
