-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.db.migrations.operations.210_to_211"


local plugin_entities = {
  {
    name = "oauth2_credentials",
    unique_keys = {"client_id"},
  },
  {
    name = "oauth2_authorization_codes",
    unique_keys = {"code"},
  },
  {
    name = "oauth2_tokens",
    unique_keys = {"access_token", "refresh_token"},
  },
}


return {
  postgres = {
    up = [[]],
  },
  cassandra = {
    up = [[]],
    teardown = function(connector)
      return operations.clean_cassandra_fields(connector, plugin_entities)
    end
  }
}
