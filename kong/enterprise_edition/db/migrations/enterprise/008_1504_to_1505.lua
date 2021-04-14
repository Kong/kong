-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
