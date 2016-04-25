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

      it("on update - increase ttl", function()
        local api, err = factory.apis:insert({
          name = "mockbin", request_host = "mockbin.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 3})
        assert.falsy(err)

        -- Retrieval
        local row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        os.execute("sleep 2")

        -- Updating the TTL to a higher value
        factory.apis:update({name = "mockbin2"}, {id = api.id}, {ttl = 3})

        os.execute("sleep 2")

        row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        os.execute("sleep 2")

        -- It has now finally expired
        row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.falsy(row)
      end)

      it("on update - decrease ttl", function()
        local api, err = factory.apis:insert({
          name = "mockbin", request_host = "mockbin.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 10})
        assert.falsy(err)

        os.execute("sleep 3")

        -- Retrieval
        local row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.truthy(row)

        -- Updating the TTL to a lower value
        local _, err = factory.apis:update({name = "mockbin2"}, {id = api.id}, {ttl = 3})
        assert.falsy(err)

        os.execute("sleep 4")

        row, err = factory.apis:find {
          id = api.id
        }
        assert.falsy(err)
        assert.falsy(row)
      end)
      
      if db_type == "postgres" then
        it("should clear old entities", function()
          local DB = require("kong.dao.postgres_db")
          local _db = DB(default_options)

          for i= 1, 4 do
            local _, err = factory.apis:insert({
              request_host = "mockbin"..i..".com",
              upstream_url = "http://mockbin.com"
            }, {ttl = 5})
            assert.falsy(err)
          end

          local _, err = factory.apis:insert({
            request_host = "mockbin-longttl.com",
            upstream_url = "http://mockbin.com"
          }, {ttl = 10})
          assert.falsy(err)

          local res, err = _db:query("SELECT COUNT(*) FROM apis")
          assert.falsy(err)
          assert.equal(5, res[1].count)

          local res, err = _db:query("SELECT COUNT(*) FROM ttls")
          assert.falsy(err)
          assert.truthy(res[1].count >= 5)

          os.execute("sleep 6")

          local ok, err = _db:clear_expired_ttl()
          assert.falsy(err)
          assert.truthy(ok)

          local res, err = _db:query("SELECT COUNT(*) FROM apis")
          assert.falsy(err)
          assert.equal(1, res[1].count)

          local res, err = _db:query("SELECT COUNT(*) FROM ttls")
          assert.falsy(err)
          assert.equal(1, res[1].count)
        end)
      end
    end)
  end)
end)
