local helpers = require "spec.spec_helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(db_type, default_options, TYPES)
  describe("Facultative options use-cases with DB: #"..db_type, function()
    local factory
    setup(function()
      factory = Factory(db_type, default_options)
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    describe("TTL", function()
      it("on insert", function()
        local api, err = factory.apis:insert({
          name = "mockbin", request_host = "mockbin.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 5})
        assert.falsy(err)

        -- Retrieval
        local row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        os.execute("sleep 5")

        row, err = factory.apis:find {
          id = api.id
        }

        assert.falsy(err)
        assert.falsy(row)
      end)

      it("on update", function()
        local api, err = factory.apis:insert({
          name = "mockbin", request_host = "mockbin.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 5})
        assert.falsy(err)

        -- Retrieval
        local row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        -- Updating the TTL to a higher value
        factory.apis:update({name = "mockbin2"}, {id = api.id}, {ttl = 10})

        os.execute("sleep 5")

        row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        os.execute("sleep 5")

        row, err = factory.apis:find {
          id = api.id
        }

        assert.falsy(err)
        assert.falsy(row)
      end)
    end)
  end)
end)
