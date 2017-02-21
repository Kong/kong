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

local helpers = require "spec.02-integration.02-dao.helpers"
local Factory = require "kong.dao.factory"

local api_tbl = {
  name = "mockbin",
  hosts = { "mockbin.com" },
  uris = { "/mockbin" },
  strip_uri = true,
  upstream_url = "https://mockbin.com"
}

helpers.for_each_dao(function(kong_config)
  describe("Model (CRUD) with DB: #"..kong_config.database, function()
    local factory, apis, oauth2_credentials
    setup(function()
      factory = assert(Factory.new(kong_config))
      apis = factory.apis

      -- DAO used for testing arrays
      oauth2_credentials = factory.oauth2_credentials
      oauth2_credentials.constraints.unique.client_id.schema.fields.consumer_id.required = false

      assert(factory:run_migrations())
    end)
    teardown(function()
      factory:truncate_tables()
      ngx.shared.cassandra:flush_expired()
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
          hosts = { "httpbin.org" },
          upstream_url = "http://httpbin.org"
        }
        assert.falsy(err)
        assert.is_table(api)
        assert.equal("httpbin", api.name)
        assert.raw_table(api)
      end)
      it("insert a valid array field and return it properly", function()
        local res, err = oauth2_credentials:insert {
          name = "test_app",
          redirect_uri = "https://mockbin.com"
        }
        assert.falsy(err)
        assert.is_table(res)
        assert.equal("test_app", res.name)
        assert.is_table(res.redirect_uri)
        assert.equal(1, #res.redirect_uri)
        assert.same({"https://mockbin.com"}, res.redirect_uri)
        assert.raw_table(res)
      end)
      it("insert a valid array field and return it properly bis", function()
        local res, err = oauth2_credentials:insert {
          name = "test_app",
          redirect_uri = "https://mockbin.com, https://mockbin.org"
        }
        assert.falsy(err)
        assert.is_table(res)
        assert.equal("test_app", res.name)
        assert.is_table(res.redirect_uri)
        assert.equal(2, #res.redirect_uri)
        assert.same({"https://mockbin.com", "https://mockbin.org"}, res.redirect_uri)
        assert.raw_table(res)
      end)
      it("add DAO-inserted values", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)
        assert.truthy(api.id)
        assert.False(api.preserve_host)
        assert.is_number(api.created_at)
        assert.equal(13, #tostring(api.created_at)) -- Make sure the timestamp has millisecond precision when returned
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
            hosts = { "hostcom" }
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
            hosts = { "fixture"..i..".com" },
            upstream_url = "http://fixture.org"
          }
          assert.falsy(err)
          assert.truthy(api)
        end

        local res, err = oauth2_credentials:insert {
          name = "test_app",
          redirect_uri = "https://mockbin.com, https://mockbin.org"
        }
        assert.falsy(err)
        assert.truthy(res)
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
      pending("retrieve all matching rows", function()
        local rows, err = apis:find_all {
          hosts = { "fixture1.com" }
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(1, #rows)
        assert.same({ "fixture1.com" }, rows[1].hosts)
        assert.unique(rows)
      end)
      pending("return matching rows bis", function()
        local rows, err = apis:find_all {
          hosts = { "fixture100.com" },
          name = "fixture_100"
        }
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(1, #rows)
        assert.equal("fixture_100", rows[1].name)
      end)
      it("return rows with arrays", function()
        local rows, err = oauth2_credentials:find_all()
        assert.falsy(err)
        assert.is_table(rows)
        assert.equal(1, #rows)
        assert.equal("test_app", rows[1].name)
        assert.is_table(rows[1].redirect_uri)
        assert.equal(2, #rows[1].redirect_uri)
        assert.same({"https://mockbin.com", "https://mockbin.org"}, rows[1].redirect_uri)
      end)
      pending("return empty table if no row match", function()
        local rows, err = apis:find_all {
          hosts = { "inexistent.com" }
        }
        assert.falsy(err)
        assert.same({}, rows)
      end)
      pending("handles non-string values", function()
        local rows, err = apis:find_all {
          hosts = { string.char(105, 213, 205, 149) }
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
            hosts = { "fixture"..i..".com" },
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
            hosts = { "fixture"..i..".com" },
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
        assert.equal(13, #tostring(api.created_at)) -- Make sure the timestamp has millisecond precision when returned
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
        api_fixture.hosts = { "updated.com" }
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
          hosts = { "inexistent.com" },
          upstream_url = "http://inexistent.com"
        }, {id = "6f204116-d052-11e5-bec8-5bc780ae6c56",})
        assert.falsy(err)
        assert.falsy(api)
      end)
      it("check constraints", function()
        local api, err = apis:insert {
          name = "i_am_unique",
          hosts = { "unique.com" },
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
        api_fixture.uris = nil

        local api, err = apis:update(api_fixture, {id = api_fixture.id})
        assert.falsy(err)
        assert.truthy(api)
        assert.not_same(api_fixture, api)
        assert.truthy(api.uris)
        assert.raw_table(api)

        api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.not_same(api_fixture, api)
        assert.truthy(api.uris)
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
          api_fixture.uris = nil

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
          api_fixture.name = nil

          local api, err = apis:update(api_fixture, api_fixture, {full = true})
          assert.truthy(err)
          assert.falsy(api)
          assert.True(err.schema)

          api, err = apis:find(api_fixture)
          assert.falsy(err)
          assert.is_table(api.hosts)
          assert.is_table(api.uris)
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
          hosts = { "inexistent.com" },
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

    describe("errors", function()
      it("returns errors prefixed by the DB type in __tostring()", function()
        local pg_port = kong_config.pg_port
        local cassandra_port = kong_config.cassandra_port
        local cassandra_timeout = kong_config.cassandra_timeout
        finally(function()
          kong_config.pg_port = pg_port
          kong_config.cassandra_port = cassandra_port
          kong_config.cassandra_timeout = cassandra_timeout
          ngx.shared.cassandra:flush_all()
        end)
        kong_config.pg_port = 3333
        kong_config.cassandra_port = 3333
        kong_config.cassandra_timeout = 1000

        assert.error_matches(function()
          local fact = assert(Factory.new(kong_config))
          assert(fact.apis:find_all())
        end, "["..kong_config.database.." error]", nil, true)
      end)
    end)
  end) -- describe
end) -- for each
