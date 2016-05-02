local function raw_table(state, arguments)
  local tbl = arguments[1]
  if not pcall(assert.falsy, getmetatable(tbl)) then
    return false
  end
  for _, v in ipairs({"ROWS", "VOID"}) do
    if tbl.type == v then
      return false
    end
  end
  if tbl.meta ~= nil then
    return false
  end
  return true
end

local say = require "say"
say:set("assertion.raw_table.positive", "Expected %s\nto be a raw table")
say:set("assertion.raw_table.negative", "Expected %s\nto not be a raw_table")
assert:register("assertion", "raw_table", raw_table, "assertion.raw_table.positive", "assertion.raw_table.negative")

local utils = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

local api_tbl = {
  name = "mockbin",
  request_host = "mockbin.com",
  request_path = "/mockbin",
  strip_request_path = true,
  upstream_url = "https://mockbin.com"
}

utils.for_each_dao(function(db_type, default_options, TYPES)
  describe("Model (CRUD) with DB: #"..db_type, function()
    local factory, apis
    setup(function()
      factory = Factory(db_type, default_options)
      apis = factory.apis
      assert(factory:run_migrations())
    end)
    teardown(function()
      factory:truncate_tables()
    end)

    describe("insert()", function()
      after_each(function()
        factory:truncate_tables()
      end)
      it("insert a valid API", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)
        for k in pairs(api_tbl) do
          assert.truthy(api[k])
        end
        -- Check that the timestamp is properly deserialized
        assert.truthy(type(api.created_at) == "number")
      end)
      it("insert a valid API bis", function()
        local api, err = apis:insert {
          name = "httpbin",
          request_host = "httpbin.org",
          upstream_url = "http://httpbin.org"
        }
        assert.falsy(err)
        assert.is_table(api)
        assert.equal("httpbin", api.name)
        assert.raw_table(api)
      end)
      it("add DAO-inserted values", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)
        assert.truthy(api.id)
        assert.False(api.preserve_host)
        assert.is_number(api.created_at)
        assert.equal(13, string.len(tostring(api.created_at))) -- Make sure the timestamp has millisecond precision when returned
      end)
      it("respect UNIQUE fields", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)

        api, err = apis:insert(api_tbl)
        assert.falsy(api)
        assert.truthy(err)
        assert.True(err.unique)
        assert.equal("already exists with value 'mockbin'", err.tbl.name)
      end)

      describe("errors", function()
        it("refuse if invalid schema", function()
          local api, err = apis:insert {
            name = "mockbin"
          }
          assert.falsy(api)
          assert.truthy(err)
          assert.True(err.schema)

          api, err = apis:insert {
            name = "mockbin",
            request_host = "hostcom"
          }
          assert.falsy(api)
          assert.truthy(err)
          assert.True(err.schema)

          api, err = apis:insert {}
          assert.falsy(api)
          assert.truthy(err)
          assert.True(err.schema)
        end)
        it("handle nil arg", function()
          assert.has_error(function()
            apis:insert()
          end, "bad argument #1 to 'insert' (table expected, got nil)")
        end)
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:insert ""
          end, "bad argument #1 to 'insert' (table expected, got string)")
        end)
      end)
    end)

    describe("find()", function()
      local api_fixture
      before_each(function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.truthy(api)
        api_fixture = api
      end)
      after_each(function()
        factory:truncate_tables()
      end)

      it("select by primary key", function()
        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.same(api_fixture, api)
        assert.raw_table(api)
      end)
      it("handle invalid field", function()
        local api, err = apis:find {
          id = "abcd",
          foo = "bar"
        }
        assert.falsy(api)
        assert.truthy(err)
        assert.True(err.schema)
      end)

      describe("errors", function()
        it("error if no primary key", function()
          assert.has_error(function()
            apis:find {name = "mockbin"}
          end, "Missing PRIMARY KEY field")
        end)
        it("handle nil arg", function()
          assert.has_error(function()
            apis:find()
          end, "bad argument #1 to 'find' (table expected, got nil)")
        end)
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:find ""
          end, "bad argument #1 to 'find' (table expected, got string)")
        end)
      end)
    end)

    describe("find_all()", function()
      setup(function()
        factory:truncate_tables()

        for i = 1, 100 do
          local api, err = apis:insert {
            name = "fixture_"..i,
            request_host = "fixture"..i..".com",
            upstream_url = "http://fixture.org"
          }
          assert.falsy(err)
          assert.truthy(api)
        end
      end)
      teardown(function()
        factory:truncate_tables()
      end)

      it("retrieve all rows", function()
        local rows, err = apis:find_all()
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(100, #rows)
        assert.raw_table(rows)
      end)
      it("retrieve all matching rows", function()
        local rows, err = apis:find_all {
          request_host = "fixture1.com"
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(1, #rows)
        assert.equal("fixture1.com", rows[1].request_host)
        assert.unique(rows)
      end)
      it("return matching rows bis", function()
        local rows, err = apis:find_all {
          request_host = "fixture100.com",
          name = "fixture_100"
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(1, #rows)
        assert.equal("fixture_100", rows[1].name)
      end)
      it("return empty table if no row match", function()
        local rows, err = apis:find_all {
          request_host = "inexistent.com"
        }
        assert.falsy(err)
        assert.same({}, rows)
      end)

      describe("errors", function()
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:find_all ""
          end, "bad argument #1 to 'find_all' (table expected, got string)")

          assert.has_error(function()
            apis:find_all {}
          end, "bad argument #1 to 'find_all' (expected table to not be empty)")
        end)
        it("handle invalid filter field", function()
          local rows, err = apis:find_all {
            foo = "bar",
            name = "fixture_100"
          }
          assert.truthy(err)
          assert.falsy(rows)
          assert.equal("unknown field", err.tbl.foo)
        end)
      end)
    end)

    describe("find_page()", function()
      setup(function()
        factory:truncate_tables()

        for i = 1, 100 do
          local api, err = apis:insert {
            name = "fixture_"..i,
            request_host = "fixture"..i..".com",
            upstream_url = "http://fixture.org"
          }
          assert.falsy(err)
          assert.truthy(api)
        end
      end)
      teardown(function()
        factory:truncate_tables()
      end)

      it("has a default_page size (100)", function()
        local rows, err = apis:find_page()
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(100, #rows)
        assert.raw_table(rows)
      end)
      it("support page_size", function()
        local rows, err = apis:find_page(nil, nil, 25)
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(25, #rows)
      end)
      it("support page_offset", function()
        local all_rows = {}
        local rows, err, offset
        for i = 1, 3 do
          rows, err, offset = apis:find_page(nil, offset, 30)
          assert.falsy(err)
          assert.equal(30, #rows)
          assert.truthy(offset)
          for _, row in ipairs(rows) do
            table.insert(all_rows, row)
          end
        end

        rows, err, offset = apis:find_page(nil, offset, 30)
        assert.falsy(err)
        assert.equal(10, #rows)
        assert.falsy(offset)

        for _, row in ipairs(rows) do
          table.insert(all_rows, row)
        end

        assert.unique(all_rows)
      end)
      it("support a filter", function()
        local rows, err, offset = apis:find_page {
          name = "fixture_2"
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.falsy(offset)
        assert.equal(1, #rows)
        assert.equal("fixture_2", rows[1].name)
      end)
      it("filter supports primary keys", function()
        local rows, err = apis:find_page {
          name = "fixture_2"
        }
        assert.falsy(err)
        local first_api = rows[1]

        local rows, err, offset = apis:find_page {
          id = first_api.id
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.falsy(offset)
        assert.equal(1, #rows)
        assert.same(first_api, rows[1])
      end)
      describe("errors", function()
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:find_page(nil, nil, "")
          end, "bad argument #3 to 'find_page' (number expected, got string)")

          assert.has_error(function()
            apis:find_page ""
          end, "bad argument #1 to 'find_page' (table expected, got string)")

          assert.has_error(function()
            apis:find_page {}
          end, "bad argument #1 to 'find_page' (expected table to not be empty)")
        end)
        it("handle invalid filter field", function()
          local rows, err = apis:find_page {
            foo = "bar",
            name = "fixture_100"
          }
          assert.truthy(err)
          assert.falsy(rows)
          assert.equal("unknown field", err.tbl.foo)
        end)
      end)
    end)

    describe("count()", function()
      setup(function()
        factory:truncate_tables()

        for i = 1, 100 do
          local api, err = apis:insert {
            name = "fixture_"..i,
            request_host = "fixture"..i..".com",
            upstream_url = "http://fixture.org"
          }
          assert.falsy(err)
          assert.truthy(api)
        end
      end)
      teardown(function()
        factory:truncate_tables()
      end)

      it("return the count of rows", function()
        local count, err = apis:count()
        assert.falsy(err)
        assert.equal(100, count)
      end)
      it("return the count of rows with filtering", function()
        local count, err = apis:count {name = "fixture_1"}
        assert.falsy(err)
        assert.equal(1, count)
      end)
      it("return 0 if filter doesn't match", function()
        local count, err = apis:count {name = "inexistent"}
        assert.falsy(err)
        assert.equal(0, count)
      end)

      describe("errors", function()
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:count ""
          end, "bad argument #1 to 'count' (table expected, got string)")

          assert.has_error(function()
            apis:count {}
          end, "bad argument #1 to 'count' (expected table to not be empty)")
        end)
        it("handle invalid filter field", function()
          local rows, err = apis:count {
            foo = "bar",
            name = "fixture_100"
          }
          assert.truthy(err)
          assert.falsy(rows)
          assert.equal("unknown field", err.tbl.foo)
        end)
      end)
    end)

    describe("update()", function()
      local api_fixture
      before_each(function()
        factory:truncate_tables()

        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        api_fixture = api
      end)
      after_each(function()
        factory:truncate_tables()
      end)

      it("update by primary key", function()
        api_fixture.name = "updated"

        local api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.falsy(err)
        assert.same(api_fixture, api)
        assert.raw_table(api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.same(api_fixture, api)
        assert.is_number(api.created_at)
        assert.equal(13, string.len(tostring(api.created_at))) -- Make sure the timestamp has millisecond precision when returned
      end)
      it("update with arbitrary filtering keys", function()
        api_fixture.name = "updated"

        local api, err = apis:update(api_fixture, {name = "mockbin"})
        assert.falsy(err)
        assert.same(api_fixture, api)
        assert.raw_table(api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.same(api_fixture, api)
      end)
      it("update multiple fields", function()
        api_fixture.name = "updated"
        api_fixture.request_host = "updated.com"
        api_fixture.upstream_url = "http://updated.com"

        local api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.falsy(err)
        assert.same(api_fixture, api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.same(api_fixture, api)
      end)
      it("update partial entity (pass schema validation)", function()
        local api, err = apis:update({name = "updated"}, {id = api_fixture.id})
        assert.falsy(err)
        assert.equal("updated", api.name)
        assert.raw_table(api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.equal("updated", api.name)
      end)
      it("return nil if no rows were affected", function()
        local api, err = apis:update({
          name = "inexistent",
          request_host = "inexistent.com",
          upstream_url = "http://inexistent.com"
        }, {id = "6f204116-d052-11e5-bec8-5bc780ae6c56",})
        assert.falsy(err)
        assert.falsy(api)
      end)
      it("check constraints", function()
        local api, err = apis:insert {
          name = "i_am_unique",
          request_host = "unique.com",
          upstream_url = "http://unique.com"
        }
        assert.falsy(err)
        assert.truthy(api)

        api_fixture.name = "i_am_unique"

        api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.truthy(err)
        assert.falsy(api)
        assert.equal("already exists with value 'i_am_unique'", err.tbl.name)
      end)
      it("check schema", function()
        api_fixture.name = 1

        local api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.truthy(err)
        assert.falsy(api)
        assert.True(err.schema)
        assert.equal("name is not a string", err.tbl.name)
      end)
      it("does not unset nil fields", function()
        api_fixture.request_path = nil

        local api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.falsy(err)
        assert.truthy(api)
        assert.not_same(api_fixture, api)
        assert.truthy(api.request_path)
        assert.raw_table(api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.not_same(api_fixture, api)
        assert.truthy(api.request_path)
      end)

      describe("full", function()
        it("update with nil fetch_keys", function()
          -- primary key is contained in entity body
          api_fixture.name = "updated-full"

          local api, err = apis:update(api_fixture, api_fixture, {full = true})
          assert.falsy(err)
          assert.truthy(api)
          assert.same(api_fixture, api)
          assert.raw_table(api)

          api, err = apis:find(api_fixture)
          assert.falsy(err)
          assert.same(api_fixture, api)
        end)
        it("unset nil fields", function()
          api_fixture.request_path = nil

          local api, err = apis:update(api_fixture, api_fixture, {full = true})
          assert.falsy(err)
          assert.truthy(api)
          assert.same(api_fixture, api)
          assert.raw_table(api)

          api, err = apis:find(api_fixture)
          assert.falsy(err)
          assert.same(api_fixture, api)
        end)
        it("check schema", function()
          api_fixture.request_path = nil
          api_fixture.request_host = nil

          local api, err = apis:update(api_fixture, api_fixture, {full = true})
          assert.truthy(err)
          assert.falsy(api)
          assert.True(err.schema)

          api, err = apis:find(api_fixture)
          assert.falsy(err)
          assert.is_string(api.request_host)
          assert.is_string(api.request_path)
        end)
      end)

      describe("errors", function()
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:update "foo"
          end, "bad argument #1 to 'update' (table expected, got string)")

          assert.has_error(function()
            apis:update {}
          end, "bad argument #1 to 'update' (expected table to not be empty)")

          assert.has_error(function()
            apis:update({a = ""}, "")
          end, "bad argument #2 to 'update' (table expected, got string)")
        end)
        it("handle nil arg", function()
          assert.has_error(function()
            apis:update()
          end, "bad argument #1 to 'update' (table expected, got nil)")
        end)
      end)
    end)

    describe("delete()", function()
      local api_fixture
      before_each(function()
        factory:truncate_tables()

        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        api_fixture = api
      end)
      after_each(function()
        factory:truncate_tables()
      end)

      it("delete a row", function()
        local res, err = apis:delete(api_fixture)
        assert.falsy(err)
        assert.same(res, api_fixture)

        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.falsy(api)
      end)
      it("return false if no rows were deleted", function()
        local res, err = apis:delete {
          id = "6f204116-d052-11e5-bec8-5bc780ae6c56",
          name = "inexistent",
          request_host = "inexistent.com",
          upstream_url = "http://inexistent.com"
        }
        assert.falsy(err)
        assert.falsy(res)

        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.truthy(api)
      end)

      describe("errors", function()
        it("handle invalid arg", function()
          assert.has_error(function()
            apis:delete "foo"
          end, "bad argument #1 to 'delete' (table expected, got string)")
        end)
        it("handle nil arg", function()
          assert.has_error(function()
            apis:delete()
          end, "bad argument #1 to 'delete' (table expected, got nil)")
        end)
      end)
    end)
  end) -- describe
end) -- for each
