-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.db.migrations.operations.200_to_210"


local plugin_entities = {
  {
    name = "hmacauth_credentials",
    primary_key = "id",
    uniques = {"username"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  }
}


return operations.ws_migrate_plugin(plugin_entities)
