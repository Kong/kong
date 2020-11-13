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
