local helpers = require "spec.helpers"
local declarative = require "kong.db.declarative"
local declarative_config = require "kong.db.schema.others.declarative_config"

local fmod    = math.fmod


local function is_valid_page(rows, err, err_t)
  if type(rows) == "table" and err == nil and err_t == nil then
    return true
  end
  return nil, "not a valid page: " .. tostring(err)
end

for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp

    -- Note by default the page size is 100, we should keep this number
    -- less than 100/(tags_per_entity)
    -- otherwise the 'limits maximum queries in single request' tests
    -- for Cassandra might fail
    local test_entity_count = 10

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "services"
      })
      if strategy == "off" then
        _G.kong.cache = helpers.get_cache(db)
      end

      for i = 1, test_entity_count do
        local service = {
          host = "example-" .. i .. ".com",
          name = "service" .. i,
          tags = { "team_a", "level_"..fmod(i, 5), "service"..i }
        }
        local row, err, err_t = bp.services:insert(service)
        assert.is_nil(err)
        assert.is_nil(err_t)
        assert.same(service.tags, row.tags)
      end

      if strategy == "off" then
        local entities = assert(bp.done())
        local dc = assert(declarative_config.load(helpers.test_conf.loaded_plugins))
        declarative.load_into_cache(dc:flatten(entities))
      end
    end)

    local removed_tags_count = 0

    it("list all entities that have tag", function()
      local rows, err, err_t, offset = db.tags:page()
      assert(is_valid_page(rows, err, err_t))
      assert.is_nil(offset)
      assert.equal(test_entity_count*3, #rows)
      for _, row in ipairs(rows) do
        assert.equal("services", row.entity_name)
      end
    end)

    it("list entity IDs by tag", function()
      local rows, err, err_t, offset = db.tags:page_by_tag("team_a")
      assert(is_valid_page(rows, err, err_t))
      assert.is_nil(offset)
      assert.equal(test_entity_count, #rows)
      for _, row in ipairs(rows) do
        assert.equal("team_a", row.tag)
      end

      rows, err, err_t, offset = db.tags:page_by_tag("team_alien")
      assert(is_valid_page(rows, err, err_t))
      assert.is_nil(offset)
      assert.equal(0, #rows)

      rows, err, err_t, offset = db.tags:page_by_tag("service1")
      assert(is_valid_page(rows, err, err_t))
      assert.is_nil(offset)
      assert.equal(1, #rows)
      for _, row in ipairs(rows) do
        assert.equal("service1", row.tag)
      end

    end)


    describe("#db update row in tags table with", function()
      local service1 = db.services:select_by_name("service1")
      assert.is_not_nil(service1)
      assert.is_not_nil(service1.id)

      local service3 = db.services:select_by_name("service3")
      assert.is_not_nil(service3)
      assert.is_not_nil(service3.id)

      -- due to the different sql in postgres stragey
      -- we need to test these two methods seperately
      local scenarios = {
        { "update", { id = service1.id }, "service1", },
        { "update_by_name", "service2", "service2"},
        { "upsert", { id = service3.id }, "service3" },
        { "upsert_by_name", "service4", "service4"},
      }
      for _, scenario in pairs(scenarios) do
        local func, key, removed_tag = unpack(scenario)

        it(func, function()
          local tags = { "team_b_" .. func, "team_a" }
          local row, err, err_t = db.services[func](db.services,
          key, { tags = tags, host = 'whatever.com' })

          assert.is_nil(err)
          assert.is_nil(err_t)
          for _, tag in ipairs(tags) do
            assert.contains(tag, row.tags)
          end

          removed_tags_count = removed_tags_count + 1

          local rows, err, err_t, offset = db.tags:page()
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(test_entity_count*3 - removed_tags_count, #rows)

          rows, err, err_t, offset = db.tags:page_by_tag("team_a")
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(test_entity_count, #rows)

          rows, err, err_t, offset = db.tags:page_by_tag("team_b_" .. func)
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(1, #rows)

          rows, err, err_t, offset = db.tags:page_by_tag(removed_tag)
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(0, #rows)
        end)

      end
    end)

    describe("#db delete row in tags table with", function()
      local service5 = db.services:select_by_name("service5")
      assert.is_not_nil(service5)
      assert.is_not_nil(service5.id)

      -- due to the different sql in postgres stragey
      -- we need to test these two methods seperately
      local scenarios = {
        { "delete", { id = service5.id }, "service5" },
        { "delete_by_name", "service6", "service6" },
      }
      for i, scenario in pairs(scenarios) do
        local delete_func, delete_key, removed_tag = unpack(scenario)

        it(delete_func, function()
          local ok, err, err_t = db.services[delete_func](db.services, delete_key)
          assert.is_true(ok)
          assert.is_nil(err)
          assert.is_nil(err_t)

          removed_tags_count = removed_tags_count + 3

          local rows, err, err_t, offset = db.tags:page()
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(test_entity_count*3 - removed_tags_count, #rows)

          rows, err, err_t, offset = db.tags:page_by_tag("team_a")
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(test_entity_count - i, #rows)

          rows, err, err_t, offset = db.tags:page_by_tag(removed_tag)
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(0, #rows)
        end)

      end
    end)

    describe("#db upsert row in tags table with", function()
      -- due to the different sql in postgres stragey
      -- we need to test these two methods seperately
      -- note this is different from test "update row in tags table with"
      -- as this test actually creats new records
      local scenarios = {
        { "upsert", { id = require("kong.tools.utils").uuid() }, { "service-upsert-1" } },
        { "upsert_by_name", "service-upsert-2", { "service-upsert-2" } },
      }
      for _, scenario in pairs(scenarios) do
        local func, key, tags = unpack(scenario)

        it(func, function()
          local row, err, err_t = db.services[func](db.services,
          key, { tags = tags, host = 'whatever.com' })

          assert.is_nil(err)
          assert.is_nil(err_t)
          for _, tag in ipairs(tags) do
            assert.contains(tag, row.tags)
          end

          local rows, err, err_t, offset = db.tags:page_by_tag(tags[1])
          assert(is_valid_page(rows, err, err_t))
          assert.is_nil(offset)
          assert.equal(1, #rows)
        end)

      end
    end)


    describe("page() by tag", function()
      local single_tag_count = 5
      local total_entities_count = 100
      for i = 1, total_entities_count do
        local service = {
          host = "anotherexample-" .. i .. ".org",
          name = "service-paging" .. i,
          tags = { "paging", "team_paging_" .. fmod(i, 5), "irrelevant_tag" }
        }
        local row, err, err_t = bp.services:insert(service)
        assert.is_nil(err)
        assert.is_nil(err_t)
        assert.same(service.tags, row.tags)
      end

      if strategy == "off" then
        local entities = assert(bp.done())
        local dc = assert(declarative_config.load(helpers.test_conf.loaded_plugins))
        declarative.load_into_cache(dc:flatten(entities))
      end

      local scenarios = { -- { tags[], expected_result_count }
        {
          { { "paging" } },
          total_entities_count,
        },
        {
          { { "paging", "team_paging_1" }, "or" },
          total_entities_count,
        },
        {
          { { "team_paging_1", "team_paging_2" }, "or" },
          total_entities_count/single_tag_count*2,
        },
        {
          { { "paging", "team_paging_1" }, "and" },
          total_entities_count/single_tag_count,
        },
        {
          { { "team_paging_1", "team_paging_2" }, "and" },
          0,
        },
      }

      local paging_size = { total_entities_count/single_tag_count, }

      for s_idx, scenario in ipairs(scenarios) do

        local opts, expected_count = unpack(scenario)
        for i = 1, 2 do -- also produce a size=nil iteration
          local size = paging_size[i]

          local scenario_name = string.format("#%d %s %s", s_idx, opts[2] and opts[2]:upper() or "",
                                              size and "with pagination" or "")

          --  page() #1 condition pagination  results count is expected

          describe(scenario_name, function()
            local seen_entities = {}
            local seen_entities_count = 0

            it("results don't overlap", function()
              local rows, err, err_t, offset
              while true do
                rows, err, err_t, offset = db.services:page(size, offset,
                  { tags = opts[1], tags_cond = opts[2] }
                )
                assert(is_valid_page(rows, err, err_t))
                for _, row in ipairs(rows) do
                  assert.is_nil(seen_entities[row.id])
                  seen_entities[row.id] = true
                  seen_entities_count = seen_entities_count + 1
                end
                if not offset then
                  break
                end
              end

            end)

            it("results count is expected", function()
              assert.equal(expected_count, seen_entities_count)
            end)
          end)
        end
      end

      local func = pending
      if strategy == "cassandra" then
        func = describe
      end

      func("limits maximum queries in single request", function()
        local match = require("luassert.match")
        -- Might be flaky because it depends on how cassandra partition/order row
        it("and exits early if PAGING_MAX_QUERY_ROUNDS exceeded", function()
          stub(ngx, "log")

          local rows, err, err_t, offset = db.services:page(2, nil,
            { tags = { "paging", "tag_notexist" }, tags_cond = 'and' })
          assert(is_valid_page(rows, err, err_t))
          assert.is_not_nil(offset)
          -- actually #rows will be 0 in this certain test case,
          -- but put as < 2(size) as it's what logically expected
          assert.is_true(#rows < 2)

          assert.stub(ngx.log).was_called()
          assert.stub(ngx.log).was_called_with(ngx.WARN, match.is_same("maximum "),  match.is_same(20),
                                        match.is_same(" rounds exceeded "),
                                        match.is_same("without retrieving required size of rows, "),
                                        match.is_same("consider lower the sparsity of tags, or increase the paging size per request"))
        end)

        local enough_page_size = total_entities_count/single_tag_count
        it("and doesn't throw warning if page size is large enough", function()
          stub(ngx, "log")

          local rows, err, err_t, offset = db.services:page(enough_page_size, nil,
            { tags = { "paging", "tag_notexist" }, tags_cond = 'and' })
          assert(is_valid_page(rows, err, err_t))
          assert.equal(0, #rows)
          assert.is_nil(offset)

          assert.stub(ngx.log).was_not_called()
        end)

        it("#flaky and returns as normal if page size is large enough", function()
          stub(ngx, "log")

          local rows, err, err_t, offset = db.services:page(enough_page_size, nil,
          { tags = { "paging", "team_paging_1" }, tags_cond = 'and' })
          assert(is_valid_page(rows, err, err_t))
          assert.equal(enough_page_size, #rows)
          if offset then
            rows, err, err_t, offset = db.services:page(enough_page_size, offset,
            { tags = { "paging", "team_paging_1" }, tags_cond = 'and' })
            assert(is_valid_page(rows, err, err_t))
            assert.equal(0, #rows)
            assert.is_nil(offset)
          end

          assert.stub(ngx.log).was_not_called()
        end)
      end)

      it("allow tags_cond omitted if there's only one tag", function()
        local rows, err, err_t, _ = db.services:page(nil, nil, { tags = { "foo" } })
        assert(is_valid_page(rows, err, err_t))
        assert.equal(0, #rows)
      end)

      it("errors on invalid options", function()
        local rows, err

        rows, err, _, _ = db.services:page(nil, nil, { tags = "oops", tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must be a table]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = true, tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must be a table]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = false, tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must be a table]], err)

        -- tags = nil is ok, in cases like /services without ?tags= query

        rows, err, _, _ = db.services:page(nil, nil, { tags = ngx.null, tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must be a table]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = -1, tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must be a table]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = { "oops", "@_@" }, tags_cond = 'and' })
        assert.is_nil(rows)
        assert.match([[tags: must only contain alphanumeric and]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = { "1", "2", "3", "4", "5", "6" } })
        assert.is_nil(rows)
        assert.match([[tags: cannot query more than 5 tags]], err)

        rows, err, _, _ = db.services:page(nil, nil, { tags = { "foo", "bar" } })
        assert.is_nil(rows)
        assert.match([[tags_cond: must be a either 'and' or 'or' when more than one tag is specified]], err)
      end)

    end)

    describe("#db errors if tag value is invalid", function()
      assert.has_error(function()
        bp.services:insert({
          host = "invalid-tag.com",
          name = "service-invalid-tag",
          tags = { "invalid tag" }
        })
      end, string.format('[%s] schema violation (tags.1: invalid value: invalid tag)', strategy))

      assert.has_error(function()
        bp.services:insert({
          host = "invalid-tag.com",
          name = "service-invalid-tag",
          tags = { "foo,bar" }
        })
      end, string.format('[%s] schema violation (tags.1: invalid value: foo,bar)', strategy))
    end)


    local func = pending
    if strategy == "postgres" then
      func = describe
    end
    func("trigger defined for table", function()
      for entity_name, dao in pairs(db.daos) do
        if dao.schema.fields.tags then
          it(entity_name, function()
            local res, err = db.connector:query(string.format([[
              SELECT event_manipulation
                FROM information_schema.triggers
              WHERE event_object_table='%s'
                AND action_statement='EXECUTE PROCEDURE sync_tags()'
                AND action_timing='AFTER'
                AND action_orientation='ROW';
            ]], entity_name))
            assert.is_nil(err)
            assert.is_table(res)
            assert.equal(3, #res)

            local evts = {}
            for i, row in ipairs(res) do
              evts[i] = row.event_manipulation
            end

            assert.contains("INSERT", evts)
            assert.contains("UPDATE", evts)
            assert.contains("DELETE", evts)

            local res, err = db.connector:query(string.format([[
              SELECT COUNT(trigger_name)
                FROM information_schema.triggered_update_columns
              WHERE event_object_table='%s'
                AND event_object_column='tags';
            ]], entity_name))
            assert.is_nil(err)
            assert.is_table(res)
            assert.is_table(res[1])
            assert.equal(1, res[1].count)
          end)
        end
      end
    end)
  end)
end
