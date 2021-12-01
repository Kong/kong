-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations_2600_2700 = require "kong.enterprise_edition.db.migrations.operations.2600_to_2700"

return {
  postgres = {
    up = [[
      DO $$
      BEGIN
      UPDATE consumers
      SET
        username = CONCAT(username, '_ADMIN_'),
        username_lower = CONCAT(username_lower, '_admin_')
      WHERE
        username !~ '_ADMIN_$'
      AND
        type = 2;
      END;
      $$;

      DO $$
      BEGIN
        ALTER TABLE IF EXISTS ONLY "license_data" ADD "year" smallint;
        ALTER TABLE IF EXISTS ONLY "license_data" ADD "month" smallint;
      EXCEPTION WHEN DUPLICATE_COLUMN THEN
        -- Do nothing, accept existing state
      END;
      $$;

      DO $$
      BEGIN
        UPDATE "license_data" SET "year" = 0 WHERE "year" IS NULL;
        UPDATE "license_data" SET "month" = 0 WHERE "month" IS NULL;
        ALTER TABLE "license_data" ALTER COLUMN "year" SET NOT NULL;
        ALTER TABLE "license_data" ALTER COLUMN "month" SET NOT NULL;
        DROP INDEX IF EXISTS license_data_key_idx;
        ALTER TABLE license_data DROP CONSTRAINT IF EXISTS license_data_pkey;
        CREATE UNIQUE INDEX IF NOT EXISTS license_data_key_idx ON license_data(node_id, year, month);
      END
      $$;

    ]]
  },

  cassandra = {
    up = [[
      /* Add temporary table for license data table */
      CREATE TABLE IF NOT EXISTS license_data_tmp (
        node_id                 uuid,
        license_creation_date   timestamp,
        req_cnt                 counter,
        PRIMARY KEY (node_id, license_creation_date)
      );
    ]],
    teardown = function(connector)
      local _, err = operations_2600_2700.cassandra_migrate_consumers(connector)
      if err then
        return nil, err
      end

      local _, err = operations_2600_2700.cassandra_migrate_license_data(connector)
      if err then
        return nil, err
      end

    end,
  },
}
