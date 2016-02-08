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
    after_each(function()
      factory:truncate_tables()
    end)

    describe("insert()", function()
      it("insert a valid API", function()
        local api, err = apis:insert(api_tbl)
        assert.falsy(err)
        assert.is_table(api)
        for k in pairs(api_tbl) do
          assert.truthy(api[k])
        end
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
      end)

      describe("invalid", function()
        it("refuse if invalid fields", function()
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

      it("select by primary key", function()
        local api, err = apis:find(api_fixture)
        assert.falsy(err)
        assert.same(api_fixture, api)
      end)
    end)
  end)
end)
