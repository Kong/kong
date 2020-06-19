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
