local helpers = require "spec.helpers"
local h = require "spec.migration_helpers.200_to_210"

describe("#db migration rate-limiting/004_200_to_210 spec", function()
  local _, db

  after_each(function()
    -- Clean up the database schema after each exercise.
    -- This prevents failed migration tests impacting other tests in the CI
    assert(db:schema_reset())
  end)

  describe("#postgres", function()
    before_each(function()
      _, db = helpers.get_db_utils("postgres", nil, nil, {
        stop_namespace = "kong.plugins.rate-limiting.migrations",
        stop_migration = "004_200_to_210",
      })
    end)

    it("adds columns", function()
      local cn = db.connector
      h.assert_not_pg_has_column(cn, "ratelimiting_metrics", "ttl", "timestamp with time zome")
      h.assert_not_pg_has_index(cn, "ratelimiting_metrics_ttl_idx")

      -- kong migrations up
      assert(helpers.run_up_migration(db, "rate-limiting",
                                      "kong.plugins.rate-limiting.migrations",
                                      "004_200_to_210"))

      h.assert_pg_has_column(cn, "ratelimiting_metrics", "ttl", "timestamp with time zone")
      h.assert_pg_has_index(cn, "ratelimiting_metrics_ttl_idx")
    end)
  end)

  -- This migration's cassandra actions are empty

end)
