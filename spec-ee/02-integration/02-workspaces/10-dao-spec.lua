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

    local sort_by_name

    lazy_setup(function()
      bp, db, _ = helpers.get_db_utils(strategy, nil, { "key-auth" })

      -- Default workspace
      s1 = bp.services:insert({ name = "s1" })
      bp.routes:insert({ name = "r1", paths = { "/" }, service = s1 })
      bp.consumers:insert({ username = "c1" })

      -- W1 workspace
      w1 = bp.workspaces:insert({ name = "w1" })
      w1s1 = bp.services:insert_ws({ name = "w1s1" }, w1)
      bp.routes:insert({ name = "w1r1", paths = { "/" }, service = s1 })
      bp.consumers:insert_ws({ username = "w1c1" }, w1)

      -- sorting function
      sort_by_name = function(a, b)
        return a.name < b.name
      end
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
      
      describe("select_all():", function()
        it("returns services for workspace [default]", function()
          local res = db.services:select_all()          
          assert.same({ s1 }, res)
        end)  

        it("returns services for workspace [w1]", function()
          local res = run_ws({ w1 }, function()
            return db.services:select_all()
          end)
          assert.same({ w1s1 }, res)
        end)
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

        it("returns shared service [s0] from workspace [default] and workspace [w1]", function()
          local res, err
          local s0 = assert(bp.services:insert({ name = "s0" }))

          -- selecting service [s0] from workspace [w1] before sharing service entity
          res, err = run_ws({ w1 }, function()
            return db.services:select({ id = s0.id })
          end)
          assert.is_nil(err)
          assert.is_nil(res)

          -- adding shared service [s0] with workspace [w1]
          assert.is_nil(workspaces.add_entity_relation("services", s0, w1))

          -- selecting shared service [s0] from workspaces [default, w1]
          assert.same(s0, run_ws({ w1 }, function()
            return db.services:select({ id = s0.id })
          end))

          -- cleanup
          local ok, err = db.services:delete({ id = s0.id })
          assert.is_nil(err)
          assert.is_true(ok)
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

        it("returns shared service [s0] from workspace [default] and workspace [w1]", function()
          local res, err
          local s0 = assert(bp.services:insert({ name = "s0" }))

          -- selecting service [s0] from workspace [w1] before sharing service entity
          res, err = run_ws({ w1 }, function()
            return db.services:page()
          end)
          assert.is_nil(err)
          assert.same({ w1s1 }, res)

          -- adding shared service [s0] with workspace [w1]
          assert.is_nil(workspaces.add_entity_relation("services", s0, w1))

          -- geting page which includes shared service [s0] from workspaces [w1]
          res = run_ws({ w1 }, function()
            return db.services:page()
          end)
          table.sort(res, sort_by_name)
        
          assert.same({ s0, w1s1 }, res)

          -- cleanup, removing shared service [s0]
          local ok, err = db.services:delete({ id = s0.id })
          assert.is_nil(err)
          assert.is_true(ok)
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

        it("returns set of services [w1s1, s0] where service [s0] is shared with workspace [w1]", function()
          local s0 = assert(bp.services:insert({ name = "s0" }))
          
          local res_services = {}
          for row in db.services:each() do
            table.insert(res_services, row)
          end
          table.sort(res_services, sort_by_name)
          assert.same({ s0, s1 }, res_services)

          -- checking existence before sharing service
          res_services = {}
          local iterator = run_ws({ w1 }, function()
            return db.services:each()
          end)
          for row in iterator do
            table.insert(res_services, row)
          end
          table.sort(res_services, sort_by_name)
          assert.same({ w1s1 }, res_services)
        
          -- adding shared service [s0] with workspace [w1]
          assert.is_nil(workspaces.add_entity_relation("services", s0, w1))

          -- checking existence after adding sharing service
          res_services = {}
          iterator = run_ws({ w1 }, function()
            return db.services:each()
          end)
          for row in iterator do
            table.insert(res_services, row)
          end
          table.sort(res_services, sort_by_name)
          assert.same({ s0, w1s1 }, res_services)
        
          -- cleanup, removing shared service [s0]
          local ok, err = db.services:delete({ id = s0.id })
          assert.is_nil(err)
          assert.is_true(ok)          
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

        it("updates shared service [s0] in workspace [w1]", function()
          local res, err
          local s0 = assert(bp.services:insert({ name = "s0" }))
          
          -- fails to update before [s0] is beign shared
          res, err = run_ws({ w1 }, function()
            return db.services:update({ id = s0.id }, { name = "s0-test" })
          end)
          assert.is_nil(res)
          assert.same("[" .. strategy .. "] could not find the entity with primary key '{id=\"" .. s0.id .. "\"}'", err)

          -- adding shared service [s0] with workspace [w1]
          assert.is_nil(workspaces.add_entity_relation("services", s0, w1))

          -- succeeds to update after [s0] is beign shared
          res, err = run_ws({ w1 }, function()
            return db.services:update({ id = s0.id }, { name = "s0-test" })
          end)
          assert.same("s0-test", res.name)
          assert.is_nil(err)

          local ok, err = db.services:delete({ id = s0.id })
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

          res, err = db.services:select({ id = s.id })
          assert.is_nil(err)
          assert.same(s, res)

          res, err = run_ws({ w1 }, function()
            return db.services:select({ id = s.id })
          end)
          assert.is_nil(res)
          assert.is_nil(err)

          local ok, err = db.services:delete({ id = s.id })
          assert.is_nil(err)
          assert.is_true(ok)
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

        it("deletes a shared service [s0] from workspace [w1]", function()
          local ok, err
          local s0 = assert(bp.services:insert({ name = "s0" }))
       
          -- checking for existence
          assert.is_nil(run_ws({ w1 }, function()
            return db.services:select({ id = s0.id })
          end))

          ok, err = run_ws({ w1 }, function()
            return db.services:delete({ id = s0.id })
          end)
          assert.is_true(ok)
          assert.is_nil(err)

          -- adding shared service [s0] with workspace [w1]
          assert.is_nil(workspaces.add_entity_relation("services", s0, w1))

          -- checking if it has been added
          assert.same(s0, run_ws({ w1 }, function()
            return db.services:select({ id = s0.id })
          end))

          -- removing from workspace [w1]
          ok, err = run_ws({ w1 }, function()
            return db.services:delete({ id = s0.id })
          end)
          assert.is_true(ok)
          assert.is_nil(err)

          -- checking if it has been removed from workspace [w1]
          assert.is_nil(run_ws({ w1 }, function()
            return db.services:select({ id = s0.id })
          end))

          -- cleanup
          ok, err = db.services:delete({ id = s0.id })
          assert.is_nil(err)
          assert.is_true(ok)
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
        it("retrieves different cache key for different workspaces", function()
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

