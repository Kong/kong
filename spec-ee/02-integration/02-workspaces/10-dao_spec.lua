local helpers    = require "spec.helpers"
local utils   = require "kong.tools.utils"
local workspaces = require "kong.workspaces"

for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local run_ws = workspaces.run_with_ws_scope
    local bp, db
    -- workspaces objects
    local s1
    local w1, w1s1

    lazy_setup(function()
      bp, db, _ = helpers.get_db_utils(strategy, {
        "routes",
        "plugins",
        "services",
        "consumers",
        "workspaces",
      }, { "key-auth" })

      -- Default workspace
      s1 = bp.services:insert({ name = "s1" })
      bp.routes:insert({ name = "r1", paths = { "/" }, service = s1 })
      bp.consumers:insert({ username = "c1" })

      -- W1 workspace
      w1 = bp.workspaces:insert({ name = "w1" })
      w1s1 = bp.services:insert_ws({ name = "w1s1" }, w1)
      bp.routes:insert({ name = "w1r1", paths = { "/" }, service = s1 })
      bp.consumers:insert_ws({ username = "w1c1" }, w1)
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    describe("workspaces", function()
      it("returns all rows", function()
        local rows = {}

        for row in db.workspaces:each() do
          table.insert(rows, row)
        end

        assert.same(2, #rows)
      end)

      describe("select():", function()
        it("returns service [s1] for workspace [default] and nil for workspace [w1]", function()
          local res
          res = db.services:select({ id = s1.id })
          assert.same(s1, res)

          res = run_ws({ w1 }, function()
            return db.services:select({ id = s1.id })
          end)
          assert.is_nil(res)
        end)

        it("returns service [w1s1] for workspace [w1] and nil for workspace [default]", function()
          local res
          res = db.services:select({ id = w1s1.id })
          assert.is_nil(res)

          res = run_ws({ w1 }, function()
            return db.services:select({ id = w1s1.id })
          end)
          assert.same(w1s1, res)
        end)
      end)

      describe("page():", function()
        it("returns page of services [s1] for workspace [default] and different set for workspace [w1]", function()
          local res
          res = db.services:page()
          assert.same({ s1 }, res)

          res = run_ws({ w1 }, function()
            return db.services:page()
          end)
          assert.not_same({ s1 }, res)
        end)
      end)

      describe("each():", function()
        it("returns set of services [s1] for workspce [default] and different set for workspace [w1]", function()
          local res_services = {}
          for row in db.services:each() do
            table.insert(res_services, row)
          end
          assert.same({ s1 }, res_services)

          local res_services = run_ws({ w1 }, function()
            local res = {}
            for row in db.services:each() do
              table.insert(res, row)
            end
            return res
          end)
          assert.not_same({ s1 }, res_services)
        end)
      end)

      describe("insert():", function()
        it("inserts a new service in a workspace [default] and not in workspace [w1]", function()
          local res
          local s, err = db.services:insert({ name = "test", host = "test" })
          assert.is_nil(err)

          res = db.services:select({ id = s.id })
          assert.same(s, res)

          res = run_ws({ w1 }, function()
            return db.services:select({ id = s.id})
          end)
          assert.is_nil(res)

          local ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)
      end)

      describe("update():", function()
        it("updates an existing service in workspace [default]", function()
          local res
          local s = bp.services:insert({ name = "update" })
          res = db.services:select({ id = s.id })
          assert.same(s, res)

          local s_updated = db.services:update({ id = s.id }, { name = "test-update" })
          res = db.services:select({ id = s.id })
          assert.same(s_updated, res)

          local ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)

        it("fails to update service [s1] from workspace [w1] which is in workspace [default]", function()
          local res, err
          local s = bp.services:insert({ name = "update" })
          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          res, err = run_ws({ w1 }, function()
            return db.services:update({ id = s.id }, { name = "test-update"})
          end)
          assert.not_same(s, res)
          assert.same("[" .. strategy .. "] could not find the entity with primary key '{id=\"" .. s.id .. "\"}'", err)

          local ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)
      end)

      describe("upsert():", function()
        it("upserts a new service in workspace [default] and fails to be retrieved from workspace [w1]", function()
          local res
          local s, err = db.services:upsert({ id = utils.uuid() }, { name = "upsert", host = "httpbin.org" })
          assert.is_nil(err)
          assert.not_nil(s)

          finally(function()
            local ok, err = db.services:delete({ id = s.id })
            assert.is_nil(err)
            assert.is_true(ok)
          end)

          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          res, err = run_ws({ w1 }, function()
            return db.services:select({ id = s.id })
          end)
          assert.is_nil(res)
          assert.is_nil(err)
        end)

        it("upserts an existing service in workspace [default]", function()
          local res, err

          -- adding new service to run test against
          local s = bp.services:insert({ name = "upsert" })
          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          -- TODO: confirm with core team when they fix upsert
          -- to accept single values without 'insert' type validation
          -- and without overriding values with default values

          -- upserting service [s] with new name
          local s_upserted, err = db.services:upsert({ id = s.id }, { name = "test-upsert", host = "httpbin.org" })

          assert.is_nil(err)
          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s_upserted, res)

          -- cleaning up service that we have created
          local ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)
      end)

      describe("delete():", function()
        it("deletes a service from workspace [default] and fails to delete service from workspace [w1]", function()
          local res, err

          -- adding new service to run test against
          local s = bp.services:insert({ name = "delete" })
          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          -- removing service from workspace [w1] using workspaces [default] service id
          local ok, err = run_ws({ w1 }, function()
            return db.services:delete({ id = s.id })
          end)
          assert.is_nil(err)
          assert.is_true(ok)

          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          -- removing service from workspace [default] using its service id
          ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)

          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.is_nil(res)
        end)
      end)

      describe("select_by_cache_key():", function()
        it("selects plugin from workspace [default] by cache key and fails to select from workspace [w1]", function()
          local res, err

          -- adding new plugin to run tests against
          local p = bp.plugins:insert({ name = "key-auth" })
          res, err = db.plugins:select({ id = p.id })
          assert.is_nil(err)
          assert.same(p, res)

          -- getting plugin cache key to test with
          local p_cache_key = db.plugins:cache_key(p)

          -- retrieving plugin entity from workspace [default]
          res, err = db.plugins:select_by_cache_key(p_cache_key)
          assert.is_nil(err)
          assert.same(p.id, res.id)

          -- retrieving plugin entity from workspace [w1]
          res, err = run_ws({ w1 }, function()
            return db.plugins:select_by_cache_key(p_cache_key)
          end)
          assert.is_nil(err)
          assert.is_nil(res)

          -- cleanup, removing plugin
          local ok, err = db.plugins:delete({ id = p.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)
      end)

      describe("cache_key():", function()
        -- XXXCORE is this really necessary? since id's are globally unique (uuids)...
        pending("retrieves different cache key for different workspaces", function()
          local res, res_1, res_2, err

          -- adding new plugin to run tests against
          local p = bp.plugins:insert({ name = "key-auth" })
          res, err = db.plugins:select({ id = p.id })
          assert.is_nil(err)
          assert.same(p, res)

          -- retrieving plugins cache key from the workspace [default]
          res_1, err = db.plugins:cache_key(p.id)
          assert.is_nil(err)
          assert.not_nil(res_1)

          -- retrieving plugins cache key from the workspace [w1]
          res_2, err = run_ws({ w1 }, function()
            return db.plugins:cache_key(p.id)
          end)
          assert.is_nil(err)
          assert.not_nil(res_2)

          assert.not_same(res_1, res_2)

          -- cleanup, removing plugin
          local ok, err = db.plugins:delete({ id = p.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)

        it("retrieves same cache key for different workspaces with skip flag on", function()
          local res, res_1, res_2,  err

          -- adding new plugin to run tests against
          local p = bp.plugins:insert({ name = "key-auth" })
          res, err = db.plugins:select({ id = p.id })
          assert.is_nil(err)
          assert.same(p, res)

          -- retrieving plugins cache key from the workspace [default]
          res_1, err = db.plugins:cache_key(p.id, nil, nil, nil, nil, true)
          assert.is_nil(err)
          assert.not_nil(res_1)

          -- retrieving plugins cache key from the workspace [w1]
          res_2, err = run_ws({ w1 }, function()
            return db.plugins:cache_key(p.id, nil, nil, nil, nil, true)
          end)
          assert.is_nil(err)
          assert.not_nil(res_2)

          assert.same(res_1, res_2)

          -- cleanup, removing plugin
          local ok, err = db.plugins:delete({ id = p.id })
          assert.is_nil(err)
          assert.is_true(ok)
        end)
      end)
    end)
  end)
end

