-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local uh = require "spec/upgrade_helpers"

describe("database migration", function()
    uh.old_after_up("has created the expected new columns", function()
      assert.table_has_column("ca_certificates", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("certificates", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("consumers", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("plugins", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("snis", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("targets", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("upstreams", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("workspaces", "updated_at", "timestamp with time zone", "timestamp")
      assert.table_has_column("clustering_data_planes", "updated_at", "timestamp with time zone", "timestamp")
    end)

    if uh.database_type() == "postgres" then
      uh.all_phases("has created the expected triggers", function ()
        assert.database_has_trigger("cluster_events_ttl_trigger")
        assert.database_has_trigger("clustering_data_planes_ttl_trigger")
      end)
    end
end)
