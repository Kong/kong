local helpers = require("spec.helpers")
local resumable_chunker = require("kong.db.resumable_chunker")

local fmod = math.fmod

for _, strategy in helpers.each_strategy() do
  describe("kong.db.resumable_chunker #" .. strategy, function()
    local db, bp

    -- Note by default the page size is 100, we should keep this number
    -- less than 100/(tags_per_entity)
    -- otherwise the 'limits maximum queries in single request' tests
    -- for Cassandra might fail
    local test_entity_count = 10

    local total_entities
    local validate_result, count, count_rows
    local random_modification, revert_modification
    local rebuild_db

    local typs = { "service", "route" }

    lazy_setup(function()
      function rebuild_db()
        bp, db = helpers.get_db_utils(strategy)

        local services = {}
        for i = 1, test_entity_count do
          local service = {
            host = "example-" .. i .. ".test",
            name = "service" .. i,
            tags = { "team_ a", "level "..fmod(i, 5), "service"..i }
          }
          local row, err, err_t = bp.services:insert(service)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(service.tags, row.tags)
          services[i] = row
        end
  
        local routes = {}
        for i = 1, test_entity_count do
          local route = {
            name = "route" .. i,
            protocols = { "http" },
            methods = { "GET" },
            paths = { "/route" .. i },
            service = services[i],
            tags = { "team_ a", "level "..fmod(i, 5), "route"..i }
          }
          local row, err, err_t = bp.routes:insert(route)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(route.tags, row.tags)
          routes[i] = row
        end
  
        for i = 1, test_entity_count do
          local plugin = {
            instance_name = "route_plugin" .. i,
            name = "key-auth",
            route = routes[i],
            tags = { "team_ a", "level "..fmod(i, 5), "route_plugin"..i }
          }
          local row, err, err_t = bp.plugins:insert(plugin)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(plugin.tags, row.tags)
        end
  
        for i = 1, test_entity_count do
          local plugin = {
            instance_name = "service_plugin" .. i,
            name = "key-auth",
            service = services[i],
            tags = { "team_ a", "level "..fmod(i, 5), "service_plugin"..i }
          }
          local row, err, err_t = bp.plugins:insert(plugin)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(plugin.tags, row.tags)
  
        end
  
        for i = 1, 1 do
          local plugin = {
            name = "key-auth",
            tags = { "team_ a", "level "..fmod(i, 5), "global_plugin"..i }
          }
          local row, err, err_t = bp.plugins:insert(plugin)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(plugin.tags, row.tags)
        end
  
        local consumers = {}
        for i = 1, test_entity_count do
          local consumer = {
            username = "consumer" .. i,
            custom_id = "custom_id" .. i,
            tags = { "team_ a", "level "..fmod(i, 5), "consumer"..i }
          }
          local row, err, err_t = bp.consumers:insert(consumer)
          assert.is_nil(err)
          assert.is_nil(err_t)
          assert.same(consumer.tags, row.tags)
          consumers[i] = row
        end
      end

      rebuild_db()

      function validate_result(counter, tolerate)
        if not tolerate then
          if not total_entities then
            total_entities = counter.n
          else
            assert.same(total_entities, counter.n)
          end
        end

        for _, typ in ipairs({ "service", "route", "route_plugin", "service_plugin" }) do
          counter[typ] = counter[typ] or {}
          if not tolerate then
            assert.same(test_entity_count, counter[typ].n, typ)
          end
          for i = 1, test_entity_count do
            counter[typ][i] = counter[typ][i] or 0
            if not tolerate then
              assert.same(1, counter[typ][i], typ .. i)
            else
              assert.truthy(counter[typ][i] >= 1, typ .. i)
            end
          end
        end
        assert.same(1, counter.global_plugin.n, "global_plugin")
        assert.same(1, counter.global_plugin[1], "global_plugin1")
      end
  
      function count(counter, row)
        local tag = row.tags and row.tags[3]
        if tag then
          local typ, n = tag:match("^(%D+)%s*(%d+)$")
          n = tonumber(n)
          counter[typ] = counter[typ] or {}
          counter[typ][n] = (counter[typ][n] or 0) + 1
          counter[typ].n = (counter[typ].n or 0) + 1
          counter.n = (counter.n or 0) + 1
        end
      end

      function count_rows(counter, rows)
        for _, row in ipairs(rows) do
          count(counter, row)
        end
      end

      local function record(typ, mod_record, row)
        table.insert(mod_record, row)
      end

      function random_modification(mod_record)
        local typ = typs[math.random(#typs)]
        local rows = assert(db[typ .. "s"]:page(100))
        if #rows == 0 then
          return
        end

        local row = rows[math.random(#rows)]

        local n = row.tags[3]:match("%d+")

        record(typ, mod_record, row)
        -- also add cascading entities
        local plugin = db.plugins:select_by_instance_name(typ .. "_plugin" .. n)
        record("plugin", mod_record, plugin)
        if typ == "service" then
          local route = db.routes:select_by_name("route" .. n)
          local routes_plugin = db.plugins:select_by_instance_name("route_plugin" .. n)
          record("route", mod_record, route)
          record("plugin", mod_record, routes_plugin)
        end
  
        db[typ .. "s"]:delete(row)
      end
  
      function revert_modification(counter, mod_record)
        count_rows(counter, mod_record)
      end
    end)

    for _, page_size in ipairs({ 1, 2, 7, 10, 13, 60, 125 }) do
      it("works for page size: " .. page_size, function()
        local counter = {}
        local chunker = resumable_chunker.from_db(kong.db)

        local rows, err, offset
        repeat
          rows, err, offset = chunker:next(page_size, offset)
          assert.is_nil(err)

          if offset then
            assert.same(page_size, #rows)
          end

          count_rows(counter, rows)
        until not offset

        validate_result(counter)
      end)
    end

    describe("lock free modification", function()
      before_each(rebuild_db)
      -- The test is slow because it requires rebuilding the database every time
      -- so we cut down the number of iterations
      for _, page_size in ipairs({ 1, 10, 13, 125 }) do
        it("for page size: #" .. page_size, function ()
          local counter = {}
          local mod_record = {}
          local chunker = resumable_chunker.from_db(kong.db)

          local rows, err, offset
          local n = 0
          repeat
            rows, err, offset = chunker:next(page_size, offset)
            assert.is_nil(err)

            if offset then
              assert.same(page_size, #rows)
            end

            n = n + page_size

            while n > test_entity_count do
              for _ = 1, math.random(0, test_entity_count) do
                random_modification(mod_record)
              end
              n = n - test_entity_count
            end

            count_rows(counter, rows)
          until not offset

          revert_modification(counter, mod_record)
          validate_result(counter, true)
        end)
      end
    end)
  end)
end
