-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local operations = require "kong.enterprise_edition.db.migrations.operations.1500_to_2100"


local plugin_entities = {
  {
    name = "oauth2_credentials",
    primary_key = "id",
    uniques = {"client_id"},
    fks = {{name = "consumer", reference = "consumers", on_delete = "cascade"}},
  },
  {
    name = "oauth2_authorization_codes",
    primary_key = "id",
    uniques = {"code"},
    fks = {
      {name = "service", reference = "services", on_delete = "cascade"},
      {name = "credential", reference = "oauth2_credentials", on_delete = "cascade"},
    },
  },
  {
    name = "oauth2_tokens",
    primary_key = "id",
    uniques = {"access_token", "refresh_token"},
    fks = {
      {name = "service", reference = "services", on_delete = "cascade"},
      {name = "credential", reference = "oauth2_credentials", on_delete = "cascade"},
    }
  },
}


return operations.ws_migrate_plugin(plugin_entities)
