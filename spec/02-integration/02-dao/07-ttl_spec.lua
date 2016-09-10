local helpers = require "spec.02-integration.02-dao.helpers"
local spec_helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

helpers.for_each_dao(function(kong_config)
  describe("TTL with #"..kong_config.database, function()
    local factory
    setup(function()
      factory = assert(Factory.new(kong_config))
      assert(factory:run_migrations())

      factory:truncate_tables()
    end)
    after_each(function()
      factory:truncate_tables()
    end)

    it("on insert", function()
      local api, err = factory.apis:insert({
        name = "mockbin",
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, {ttl = 1})
      assert.falsy(err)

      local row, err = factory.apis:find {id = api.id}
      assert.falsy(err)
      assert.truthy(row)

      ngx.sleep(1)

      spec_helpers.wait_until(function()
        row, err = factory.apis:find {id = api.id}
        assert.falsy(err)
        return row == nil
      end, 1)
    end)

    it("on update", function()
      local api, err = factory.apis:insert({
        name = "mockbin",
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, {ttl = 1})
      assert.falsy(err)

      local row, err = factory.apis:find {id = api.id}
      assert.falsy(err)
      assert.truthy(row)

      -- Updating the TTL to a higher value
      factory.apis:update({name = "mockbin2"}, {id = api.id}, {ttl = 2})

      ngx.sleep(1)

      row, err = factory.apis:find {id = api.id}
      assert.falsy(err)
      assert.truthy(row)

      ngx.sleep(1)

      spec_helpers.wait_until(function()
        row, err = factory.apis:find {id = api.id}
        assert.falsy(err)
        return row == nil
      end, 1)
    end)

    if kong_config.database == "postgres" then
      it("clears old entities", function()
        local DB = require "kong.dao.postgres_db"
        local _db = DB(kong_config)

        for i = 1, 4 do
          local _, err = factory.apis:insert({
            request_host = "mockbin"..i..".com",
            upstream_url = "http://mockbin.com"
          }, {ttl = 1})
          assert.falsy(err)
        end

        local _, err = factory.apis:insert({
          request_host = "mockbin-longttl.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 3})
        assert.falsy(err)

        local res, err = _db:query("SELECT COUNT(*) FROM apis")
        assert.falsy(err)
        assert.equal(5, res[1].count)

        res, err = _db:query("SELECT COUNT(*) FROM ttls")
        assert.falsy(err)
        assert.truthy(res[1].count >= 5)

        ngx.sleep(2)

        local ok, err = _db:clear_expired_ttl()
        assert.falsy(err)
        assert.truthy(ok)

        spec_helpers.wait_until(function()
          local res_apis, err = _db:query("SELECT COUNT(*) FROM apis")
          assert.falsy(err)

          local res_ttls, err = _db:query("SELECT COUNT(*) FROM ttls")
          assert.falsy(err)

          return res_apis[1].count == 1 and res_ttls[1].count == 1
        end, 1)
      end)
    end
  end)
end)
