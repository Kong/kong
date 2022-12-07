-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      -- add rbac_user_name,request_source to audit_requests
      DO $$
        BEGIN
        ALTER TABLE IF EXISTS ONLY "audit_requests" ADD COLUMN "rbac_user_name" TEXT;
        ALTER TABLE IF EXISTS ONLY "audit_requests" ADD COLUMN "request_source" TEXT; 
        EXCEPTION WHEN duplicate_column THEN
          -- Do nothing, accept existing state
        END;
      $$;
    ]]
  },

  cassandra = {
    up = [[
      -- add rbac_user_name,request_source to audit_requests
      ALTER TABLE audit_requests ADD rbac_user_name text;
      ALTER TABLE audit_requests ADD request_source text;
    ]]
  },
}
