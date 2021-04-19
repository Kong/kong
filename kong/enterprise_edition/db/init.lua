-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local migrate_core_entities = require "kong.enterprise_edition.db.migrations.migrate_core_entities"


local ee_db = {}


local function prefix_err(self, err)
  return "[" .. self.infos.strategy .. " error] " .. err
end


function ee_db.run_core_entity_migrations(opts)
  local ok, err = kong.db.connector:connect_migrations()
  if not ok then
    return nil, prefix_err(kong.db, err)
  end

  return migrate_core_entities(kong.db, opts)
end


return ee_db
