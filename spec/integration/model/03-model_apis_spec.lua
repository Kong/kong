local inspect = require "inspect"

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
  describe("Model (APIs) with DB: #"..db_type, function()
    local factory, apis
    setup(function()
      factory = Factory(db_type, default_options)
      apis = factory.apis
      assert(factory:run_migrations())
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
      end)
      it("add DAO-inserted values", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)
        assert.truthy(api.id)
        if db_type == TYPES.CASSANDRA then
          assert.is_number(api.created_at)
        elseif db_type == TYPES.POSTGRES then
          assert.is_string(api.created_at)
        end
      end)
      it("respect UNIQUE fields", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)

        api, err = apis:insert(api_tbl)
        assert.falsy(api)
        assert.truthy(err)
        assert.True(err.unique)
        assert.equal("already exists with value 'mockbin'", err.err_tbl.name)
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
      end)
      it("handle invalid field", function()
        local api, err = apis:find {
          id = "abcd",
          foo = "bar"
        }
        assert.falsy(api)
        if db_type == TYPES.CASSANDRA then
          assert.truthy(err)
          assert.True(err.db)
          assert.equal("[Invalid] UUID should be 16 or 0 bytes (2)", tostring(err))
        elseif db_err == TYPES.POSTGRES then
          assert.falsy(err)
        end
      end)

      describe("errors", function()
        it("select returns nothing if no primary key", function()
          assert.has_error(function()
            apis:find {name = "mockbin"}
          end, "Missing PRIMARY KEY field")
        end)
        it("handle nil arg", function()
          assert.has_error(function()
            apis:find()
          end, "bad argument #1 to 'find' (table expected, got nil)")
        end)
      end)
    end)

    describe("find_all()", function()
      setup(function()
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
        local apis, err = apis:find_all()
        assert.falsy(err)
        assert.is_table(apis)
        assert.equal(100, #apis)
      end)
      it("retrieve all matching rows", function()
        local apis, err = apis:find_all {
          request_host = "fixture1.com"
        }
        assert.falsy(err)
        assert.is_table(apis)
        assert.equal(1, #apis)
        assert.equal("fixture1.com", apis[1].request_host)
      end)
      it("return matching rows bis", function()
        local apis, err = apis:find_all {
          request_host = "fixture100.com",
          name = "fixture_100"
        }
        assert.falsy(err)
        assert.is_table(apis)
        assert.equal(1, #apis)
        assert.equal("fixture_100", apis[1].name)
      end)
      it("return empty table if no row match", function()
        local apis, err = apis:find_all {
          request_host = "inexistent.com"
        }
        assert.falsy(err)
        assert.same({}, apis)
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
        it("handle invalid field", function()
          assert.has_error(function()
            apis:find_all {foo = "bar"}
          end, "bad argument #1 to 'find_all' (field 'foo' not in schema)")
        end)
      end)
    end)

    describe("count()", function()
      setup(function()
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
    end)
  end)
end)
