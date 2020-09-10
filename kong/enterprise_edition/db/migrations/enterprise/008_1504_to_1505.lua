return {
  postgres = {
    up = [[
      -- update all old records that doesn't have current timestamp for `license_creation_date` field after migrations
      UPDATE license_data SET license_creation_date = CURRENT_TIMESTAMP WHERE license_creation_date IS NULL;
    ]],
    teardown = function(connector)
      -- Risky migrations
    end
  },
  cassandra = {
    up = [[]],
    teardown = function(connector)
      -- Risky migrations
    end
  }
}
