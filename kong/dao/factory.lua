local DAO = require "kong.dao.dao"
local utils = require "kong.tools.utils"
local ModelFactory = require "kong.dao.model_factory"

local CORE_MODELS = {
  "apis",
  "consumers",
  "plugins",
  "ssl_certificates",
  "ssl_servers_names",
  "upstreams",
  "targets",
}

-- returns db errors as strings, including the initial `nil`
local function ret_error_string(db_name, res, err)
  res, err = DAO.ret_error(db_name, res, err)
  return res, tostring(err)
end

local _M = {}

function _M:__index(key)
  local daos = rawget(self, "daos")
  if daos and daos[key] then
    return daos[key]
  else
    return _M[key]
  end
end

local function build_constraints(schemas)
  local all_constraints = {}
  for m_name, schema in pairs(schemas) do
    local constraints = {foreign = {}, unique = {}}
    for col, field in pairs(schema.fields) do
      if type(field.foreign) == "string" then
        local f_entity, f_field = unpack(utils.split(field.foreign, ":"))
        if f_entity ~= nil and f_field ~= nil then
          local f_schema = schemas[f_entity]
          constraints.foreign[col] = {
            table = f_schema.table,
            schema = f_schema,
            col = f_field,
            f_entity = f_entity
          }
        end
      end
      if field.unique then
        constraints.unique[col] = {
          table = schema.table,
          schema = schema
        }
      end
    end
    all_constraints[m_name] = constraints
  end

  return all_constraints
end

local function load_daos(self, schemas, constraints)
  for m_name, schema in pairs(schemas) do
    if constraints[m_name] ~= nil and constraints[m_name].foreign ~= nil then
      for col, f_constraint in pairs(constraints[m_name].foreign) do
        local parent_name = f_constraint.f_entity
        local parent_constraints = constraints[parent_name]
        if parent_constraints.cascade == nil then
          parent_constraints.cascade = {}
        end

        parent_constraints.cascade[m_name] = {
          table = schema.table,
          schema = schema,
          f_col = col,
          col = f_constraint.col
        }
      end
    end
  end

  for m_name, schema in pairs(schemas) do
    self.daos[m_name] = DAO(self.db, ModelFactory(schema), schema,
                            constraints[m_name])
  end
end

function _M.new(kong_config)
  local self = {
    db_type = kong_config.database,
    daos = {},
    additional_tables = {},
    kong_config = kong_config,
    plugin_names = kong_config.plugins or {}
  }

  local DB = require("kong.dao.db." .. self.db_type)
  local db, err = DB.new(kong_config)
  if not db then
    return ret_error_string(self.db_type, nil, err)
  end

  self.db = db

  local schemas = {}
  for _, m_name in ipairs(CORE_MODELS) do
    schemas[m_name] = require("kong.dao.schemas." .. m_name)
  end

  for plugin_name in pairs(self.plugin_names) do
    local has_schema, plugin_schemas = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".daos")
    if has_schema then
      if plugin_schemas.tables then
        for _, v in ipairs(plugin_schemas.tables) do
          table.insert(self.additional_tables, v)
        end
      else
        for k, v in pairs(plugin_schemas) do
          schemas[k] = v
        end
      end
    end
  end

  local constraints = build_constraints(schemas)
  load_daos(self, schemas, constraints)

  return setmetatable(self, _M)
end

function _M:init()
  return self.db:init()
end

function _M:init_worker()
  return self.db:init_worker()
end

function _M:set_events_handler(events)
  for _, dao in pairs(self.daos) do
    dao.events = events
  end
end

-- Migrations

function _M:infos()
  return self.db:infos()
end

function _M:drop_schema()
  for _, dao in pairs(self.daos) do
    self.db:drop_table(dao.table)
  end

  if self.additional_tables then
    for _, v in ipairs(self.additional_tables) do
      self.db:drop_table(v)
    end
  end

  if self.db.additional_tables then
    for _, v in ipairs(self.db.additional_tables) do
      self.db:drop_table(v)
    end
  end

  self.db:drop_table("schema_migrations")
end

function _M:truncate_table(dao_name)
  self.db:truncate_table(self.daos[dao_name].table)
end

function _M:truncate_tables()
  for _, dao in pairs(self.daos) do
    self.db:truncate_table(dao.table)
  end

  if self.db.additional_tables then
    for _, v in ipairs(self.db.additional_tables) do
      self.db:truncate_table(v)
    end
  end

  if self.additional_tables then
    for _, v in ipairs(self.additional_tables) do
      self.db:truncate_table(v)
    end
  end
end

function _M:migrations_modules()
  local migrations = {
    core = require("kong.dao.migrations." .. self.db_type)
  }

  for plugin_name in pairs(self.plugin_names) do
    local ok, plugin_mig = utils.load_module_if_exists("kong.plugins." .. plugin_name .. ".migrations." .. self.db_type)
    if ok then
      migrations[plugin_name] = plugin_mig
    end
  end

  do
    -- check that migrations have a name, and that no two migrations have the
    -- same name.
    local migration_names = {}

    for plugin_name, plugin_migrations in pairs(migrations) do
      for i, migration in ipairs(plugin_migrations) do
        local s = plugin_name == "core" and
                    "'core'" or "plugin '" .. plugin_name .. "'"

        if migration.name == nil then
          return nil, string.format("migration '%d' for %s has no " ..
                                    "name", i, s)
        end

        if type(migration.name) ~= "string" then
          return nil, string.format("migration '%d' for %s must be a string",
                                    i, s)
        end

        if migration_names[migration.name] then
          return nil, string.format("migration '%s' (%s) already " ..
                                    "exists; migrations must have unique names",
                                    migration.name, s)
        end

        migration_names[migration.name] = true
      end
    end
  end

  return migrations
end

function _M:current_migrations()
  local rows, err = self.db:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations = {}
  for _, row in ipairs(rows) do
    cur_migrations[row.id] = row.migrations
  end
  return cur_migrations
end

local function migrate(self, identifier, migrations_modules, cur_migrations, on_migrate, on_success)
  local migrations = migrations_modules[identifier]
  local recorded = cur_migrations[identifier] or {}
  local to_run = {}
  for i, mig in ipairs(migrations) do
    if mig.name ~= recorded[i] then
      to_run[#to_run + 1] = mig
    end
  end

  if #to_run > 0 and on_migrate then
    -- we have some migrations to run
    on_migrate(identifier, self.db:infos())
  end

  for _, migration in ipairs(to_run) do
    local err
    local mig_type = type(migration.up)
    if mig_type == "string" then
      err = self.db:queries(migration.up)
    elseif mig_type == "function" then
      err = migration.up(self.db, self.kong_config, self)
    end

    if err then
      return nil, string.format("Error during migration %s: %s", migration.name, err)
    end

    -- record success
    local ok, err = self.db:record_migration(identifier, migration.name)
    if not ok then
      return nil, string.format("Error recording migration %s: %s", migration.name, err)
    end

    if on_success then
      on_success(identifier, migration.name, self.db:infos())
    end
  end

  return true, nil, #to_run
end

local function default_on_migrate(identifier, db_infos)
  local log = require "kong.cmd.utils.log"
  log("migrating %s for %s %s",
      identifier, db_infos.desc, db_infos.name)
end

local function default_on_success(identifier, migration_name, db_infos)
  local log = require "kong.cmd.utils.log"
  log("%s migrated up to: %s",
      identifier, migration_name)
end

function _M:are_migrations_uptodate()
  local migrations_modules, err = self:migrations_modules()
  if not migrations_modules then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations, err = self:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil,
                            "could not retrieve current migrations: " .. err)
  end

  local log = require "kong.cmd.utils.log"

  for module, migrations in pairs(migrations_modules) do
    for _, migration in ipairs(migrations) do
      if not (cur_migrations[module] and
              utils.table_contains(cur_migrations[module], migration.name))
      then
        local infos = self.db:infos()
        log.warn("%s %s '%s' is missing migration: (%s) %s",
                 self.db_type, infos.desc, infos.name, module, migration.name or "(no name)")
        return ret_error_string(self.db.name, nil, "the current database "   ..
                                "schema does not match this version of "     ..
                                "Kong. Please run `kong migrations up` "     ..
                                "to update/initialize the database schema. " ..
                                "Be aware that Kong migrations should only " ..
                                "run from a single node, and that nodes "    ..
                                "running migrations concurrently will "      ..
                                "conflict with each other and might "        ..
                                "corrupt your database schema!")
      end
    end
  end

  return true
end

function _M:check_schema_consensus()
  if self.db.name ~= "cassandra" then
    return true -- only applicable for cassandra
  end

  local log = require "kong.cmd.utils.log"

  log.verbose("checking Cassandra schema consensus...")

  local ok, err = self.db:check_schema_consensus()
  if err then
    return ret_error_string(self.db.name, nil,
                            "failed to check for schema consensus: " .. err)
  end

  log.verbose("Cassandra schema consensus: %s",
              ok ~= nil and "reached" or "not reached")

  return ok
end

function _M:run_migrations(on_migrate, on_success)
  on_migrate = on_migrate or default_on_migrate
  on_success = on_success or default_on_success

  local log = require "kong.cmd.utils.log"

  log.verbose("running datastore migrations")

  if self.db.name == "cassandra" then
    local ok, err = self.db:first_coordinator()
    if not ok then
      return ret_error_string(self.db.name, nil,
                              "could not find coordinator: " .. err)
    end
  end

  local migrations_modules, err = self:migrations_modules()
  if not migrations_modules then
    return ret_error_string(self.db.name, nil, err)
  end

  local cur_migrations, err = self:current_migrations()
  if err then
    return ret_error_string(self.db.name, nil,
                            "could not retrieve current migrations: " .. err)
  end

  local ok, err, migrations_ran = migrate(self, "core", migrations_modules, cur_migrations, on_migrate, on_success)
  if not ok then
    return ret_error_string(self.db.name, nil, err)
  end

  for identifier in pairs(migrations_modules) do
    if identifier ~= "core" then
      local ok, err, n_ran = migrate(self, identifier, migrations_modules, cur_migrations, on_migrate, on_success)
      if not ok then return ret_error_string(self.db.name, nil, err)
      else
        migrations_ran = migrations_ran + n_ran
      end
    end
  end

  if migrations_ran > 0 then
    log("%d migrations ran", migrations_ran)

    if self.db.name == "cassandra" then
      log("waiting for Cassandra schema consensus (%dms timeout)...",
          self.db.cluster.max_schema_consensus_wait)

      local ok, err = self.db:wait_for_schema_consensus()
      if not ok then
        return ret_error_string(self.db.name, nil,
                                "failed to wait for schema consensus: " .. err)
      end

      log("Cassandra schema consensus: reached")
    end
  end

  if self.db.name == "cassandra" then
    local ok, err = self.db:close_coordinator()
    if not ok then
      return ret_error_string(self.db.name, nil,
                              "could not close coordinator: " .. err)
    end
  end

  log.verbose("migrations up to date")

  return true
end

return _M
