-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Wants to make licenses table like
-- CREATE TABLE IF NOT EXISTS licenses (
--   "id"            UUID                        PRIMARY KEY,
--   "payload"       TEXT                        NOT NULL UNIQUE,
--   "created_at"    TIMESTAMP WITH TIME ZONE,
--   "updated_at"    TIMESTAMP WITH TIME ZONE
-- );

return {
  postgres = {
    up = [[

      ALTER TABLE IF EXISTS ONLY "licenses" ALTER COLUMN "created_at" DROP DEFAULT;
      ALTER TABLE IF EXISTS ONLY "licenses" ALTER COLUMN "created_at" TYPE TIMESTAMP WITH TIME ZONE USING "created_at" AT TIME ZONE 'UTC';

      ALTER TABLE IF EXISTS ONLY "licenses" ALTER COLUMN "updated_at" DROP DEFAULT;
      ALTER TABLE IF EXISTS ONLY "licenses" ALTER COLUMN "updated_at" TYPE TIMESTAMP WITH TIME ZONE USING "updated_at" AT TIME ZONE 'UTC';

    ]],
    teardown = function(connector)
      assert(connector:query([[
        DELETE FROM licenses WHERE payload IS NULL;
        ALTER TABLE IF EXISTS ONLY "licenses" ALTER COLUMN "payload" SET NOT NULL;

        DELETE FROM licenses WHERE id IN (
          SELECT l.id FROM licenses l, licenses ll
          WHERE l.payload = ll.payload
          AND l.id < ll.id
        );

        ALTER TABLE "licenses" DROP CONSTRAINT IF EXISTS "licenses_payload_key";
        ALTER TABLE IF EXISTS ONLY "licenses" ADD CONSTRAINT "licenses_payload_key" UNIQUE (payload);
      ]]))
    end,
  },

  cassandra = {
    up = [[]],
  },
}
