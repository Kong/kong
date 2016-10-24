local helpers = require "spec.helpers"
local Factory = require "kong.dao.factory"

for conf, database in helpers.for_each_db() do
  describe("TTL with #" .. database, function()
    local factory
    setup(function()
      factory = assert(Factory.new(conf))
      assert(factory:run_migrations())
    end)
    before_each(function()
      factory:truncate_tables()
    end)

    it("on insert", function()
      local api = assert(factory.apis:insert({
        name = "mockbin",
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, {ttl = 1}))

      assert(factory.apis:find {id = api.id})

      ngx.sleep(1)

      helpers.wait_until(function()
        local row, err = factory.apis:find {id = api.id}
        assert.falsy(err)
        return row == nil
      end, 1)
    end)

    it("on update", function()
      local api = assert(factory.apis:insert({
        name = "mockbin",
        request_host = "mockbin.com",
        upstream_url = "http://mockbin.com"
      }, {ttl = 1}))

      assert(factory.apis:find {id = api.id})

      -- Updating the TTL to a higher value
      assert(factory.apis:update({name = "mockbin2"}, {id = api.id}, {ttl = 2}))

      ngx.sleep(1)

      assert(factory.apis:find {id = api.id})

      ngx.sleep(1)

      helpers.wait_until(function()
        local row, err = factory.apis:find {id = api.id}
        assert.falsy(err)
        return row == nil
      end, 1)
    end)

    if database == "postgres" then
      it("clears old entities", function()
        local DB = require "kong.dao.db.postgres"
        local _db = DB.new(conf)

        for i = 1, 4 do
          assert(factory.apis:insert({
            request_host = "mockbin"..i..".com",
            upstream_url = "http://mockbin.com"
          }, {ttl = 1}))
        end

        assert(factory.apis:insert({
          request_host = "mockbin-longttl.com",
          upstream_url = "http://mockbin.com"
        }, {ttl = 3}))

        local res = assert(_db:query("SELECT COUNT(*) FROM apis"))
        assert.equal(5, res[1].count)

        res = assert(_db:query("SELECT COUNT(*) FROM ttls"))
        assert.truthy(res[1].count >= 5)

        ngx.sleep(2)

        assert(_db:clear_expired_ttl())

        helpers.wait_until(function()
          local res_apis = assert(_db:query("SELECT COUNT(*) FROM apis"))
          local res_ttls = assert(_db:query("SELECT COUNT(*) FROM ttls"))

          return res_apis[1].count == 1 and res_ttls[1].count == 1
        end, 1)
      end)
    end
  end)
end
