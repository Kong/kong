local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  local postgres_only = strategy == "postgres" and describe or pending
  postgres_only("postgres ttl cleanup logic", function()
    describe("ttl cleanup timer #postgres", function()
      local bp, db, consumer1
      lazy_setup(function()
        bp, db = helpers.get_db_utils("postgres", {
          "routes",
          "services",
          "plugins",
          "consumers",
          "keyauth_credentials"
        })

        consumer1 = bp.consumers:insert {
          username = "conumer1"
        }

        assert(helpers.start_kong({
          database = strategy,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        db:truncate()
      end)

      it("init_worker should run ttl cleanup in background timer", function ()
        helpers.clean_logfile()
        local names_of_table_with_ttl = db.connector._get_topologically_sorted_table_names(db.strategies)
        assert.truthy(#names_of_table_with_ttl > 0)
        for _, name in ipairs(names_of_table_with_ttl) do
          assert.errlog().has.line([[cleaning up expired rows from table ']] .. name .. [[' took \d+\.\d+ seconds]], false, 120)
        end

        local _ = bp.keyauth_credentials:insert({
          key = "secret1",
          consumer = { id = consumer1.id },
        }, {ttl = 3})
        helpers.clean_logfile()

        helpers.wait_until(function()
          return assert.errlog().has.line([[cleaning up expired rows from table ']] .. "keyauth_credentials" .. [[' took \d+\.\d+ seconds]], false, 120)
        end, 120)

        local ok, err = db.connector:query("SELECT * FROM keyauth_credentials")
        assert.is_nil(err)
        assert.same(0, #ok)
      end)
    end)
  end)
end
