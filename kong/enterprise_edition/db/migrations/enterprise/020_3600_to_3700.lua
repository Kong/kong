-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


return {
  postgres = {
    up = [[
      DO $$
        BEGIN
          -- the default is the same as for audit_requests
          ALTER TABLE IF EXISTS ONLY "audit_objects" ADD "request_timestamp" TIMESTAMP WITHOUT TIME ZONE DEFAULT (CURRENT_TIMESTAMP(3) AT TIME ZONE 'utc'::text);

          -- update all existing records
          -- note that the minimum timestamp is 1 since our typedefs do not allow timestamp of value 0
          UPDATE "audit_objects" SET "request_timestamp" = TO_TIMESTAMP(1);

          CREATE INDEX IF NOT EXISTS "audit_requests_request_timestamp_idx" ON "audit_requests" ("request_timestamp");
          CREATE INDEX IF NOT EXISTS "audit_objects_request_timestamp_idx" ON "audit_objects" ("request_timestamp");
        EXCEPTION WHEN UNDEFINED_COLUMN OR DUPLICATE_COLUMN THEN
          -- do nothing, accept existing state
      END$$;
    ]]
  }
}
