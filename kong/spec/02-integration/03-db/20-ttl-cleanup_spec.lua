local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
  local postgres_only = strategy == "postgres" and describe or pending
  postgres_only("postgres ttl cleanup logic", function()
    describe("ttl cleanup timer #postgres", function()
      local bp, db, consumer1
      lazy_setup(function()
        helpers.clean_logfile()

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

        local _ = bp.keyauth_credentials:insert({
          key = "secret1",
          consumer = { id = consumer1.id },
        }, {ttl = 3})

        assert(helpers.start_kong({
          database = strategy,
          log_level = "debug",
          _debug_pg_ttl_cleanup_interval = 3,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        db:truncate()
      end)

      it("init_worker should run ttl cleanup in background timer", function ()
        helpers.pwait_until(function()
          assert.errlog().has.line([[cleaning up expired rows from table ']] .. "keyauth_credentials" .. [[' took .+ seconds]], false, 2)
        end, 5)

        local ok, err = db.connector:query("SELECT * FROM keyauth_credentials")
        assert.is_nil(err)
        assert.same(0, #ok)

        -- Check all tables are cleaned so that we don't need to wait for another loop
        local names_of_table_with_ttl = db.connector._get_topologically_sorted_table_names(db.strategies)
        assert.truthy(#names_of_table_with_ttl > 0)

        for _, name in ipairs(names_of_table_with_ttl) do
          assert.errlog().has.line([[cleaning up expired rows from table ']] .. name .. [[' took .+ seconds]], false, 2)
        end
      end)
    end)
  end)
end
