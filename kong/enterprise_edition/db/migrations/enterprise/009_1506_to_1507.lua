-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE INDEX IF NOT EXISTS login_attempts_ttl_idx ON login_attempts (ttl);
      CREATE INDEX IF NOT EXISTS audit_requests_ttl_idx ON audit_requests (ttl);
      CREATE INDEX IF NOT EXISTS audit_objects_ttl_idx ON audit_objects (ttl);
    ]],
    teardown = function(connector)

    end
  },
  cassandra = {
    -- cassandra expires rows by ttl in the database itself
    up = [[
    ]],
    teardown = function(connector)
    end
  }
}
