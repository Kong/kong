local DAO = require "kong.dao.dao"
local utils = require "kong.tools.utils"
local ModelFactory = require "kong.dao.model_factory"

local CORE_MODELS = {"apis", "consumers", "plugins", "nodes"}
local _db

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

local function load_daos(self, schemas, constraints, events_handler)
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
    self.daos[m_name] = DAO(_db, ModelFactory(schema), schema, constraints[m_name], events_handler)
  end
end

function _M.new(kong_config, events_handler)
  local factory = {
    db_type = kong_config.database,
    daos = {},
    kong_config = kong_config,
    plugin_names = kong_config.plugins or {}
  }

  local DB = require("kong.dao.db."..factory.db_type)
  local db, err = DB.new(kong_config)
  if not db then return ret_error_string(factory.db_type, nil, err) end

  _db = db -- avoid setting a previous upvalue to `nil` in case `DB.new()` fails

  local schemas = {}
  for _, m_name in ipairs(CORE_MODELS) do
    schemas[m_name] = require("kong.dao.schemas."..m_name)
  end

  for plugin_name in pairs(factory.plugin_names) do
    local has_dao, plugin_daos = utils.load_module_if_exists("kong.plugins."..plugin_name..".dao."..factory.db_type)
    if has_dao then
      for k, v in pairs(plugin_daos) do
        factory.daos[k] = v(kong_config)
      end
    end

    local has_schema, plugin_schemas = utils.load_module_if_exists("kong.plugins."..plugin_name..".daos")
    if has_schema then
      for k, v in pairs(plugin_schemas) do
        schemas[k] = v
      end
    end
  end

  local constraints = build_constraints(schemas)
  load_daos(factory, schemas, constraints, events_handler)

  return setmetatable(factory, _M)
end

function _M:init()
  return _db:init()
end

-- Migrations

function _M:infos()
  return _db:infos()
end

function _M:drop_schema()
  for _, dao in pairs(self.daos) do
    _db:drop_table(dao.table)
  end

  if _db.additional_tables then
    for _, v in ipairs(_db.additional_tables) do
      _db:drop_table(v)
    end
  end

  _db:drop_table("schema_migrations")
end

function _M:truncate_table(dao_name)
  _db:truncate_table(self.daos[dao_name].table)
end

function _M:truncate_tables()
  for _, dao in pairs(self.daos) do
    _db:truncate_table(dao.table)
  end

  if _db.additional_tables then
    for _, v in ipairs(_db.additional_tables) do
      _db:truncate_table(v)
    end
  end
end

function _M:migrations_modules()
  local migrations = {
    core = require("kong.dao.migrations."..self.db_type)
  }

  for plugin_name in pairs(self.plugin_names) do
    local ok, plugin_mig = utils.load_module_if_exists("kong.plugins."..plugin_name..".migrations."..self.db_type)
    if ok then
      migrations[plugin_name] = plugin_mig
    end
  end

  return migrations
end

function _M:current_migrations()
  local rows, err = _db:current_migrations()
  if err then return ret_error_string(_db.name, nil, err) end

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
    on_migrate(identifier, _db:infos())
  end

  for _, migration in ipairs(to_run) do
    local err
    local mig_type = type(migration.up)
    if mig_type == "string" then
      err = _db:queries(migration.up)
    elseif mig_type == "function" then
      err = migration.up(_db, self.kong_config, self)
    end

    if err then
      return false, string.format("Error during migration %s: %s", migration.name, err)
    end

    -- record success
    err = _db:record_migration(identifier, migration.name)
    if err then
      return false, string.format("Error recording migration %s: %s", migration.name, err)
    end

    if on_success then
      on_success(identifier, migration.name, _db:infos())
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

function _M:run_migrations(on_migrate, on_success)
  on_migrate = on_migrate or default_on_migrate
  on_success = on_success or default_on_success

  local log = require "kong.cmd.utils.log"

  log.verbose("running datastore migrations")

  local migrations_modules = self:migrations_modules()
  local cur_migrations, err = self:current_migrations()
  if err then return ret_error_string(_db.name, nil, err) end

  local ok, err, migrations_ran = migrate(self, "core", migrations_modules, cur_migrations, on_migrate, on_success)
  if not ok then return ret_error_string(_db.name, nil, err) end

  for identifier in pairs(migrations_modules) do
    if identifier ~= "core" then
      local ok, err, n_ran = migrate(self, identifier, migrations_modules, cur_migrations, on_migrate, on_success)
      if not ok then return ret_error_string(_db.name, nil, err)
      else
        migrations_ran = migrations_ran + n_ran
      end
    end
  end

  if migrations_ran > 0 then
    log("%d migrations ran", migrations_ran)
  end

  log.verbose("migrations up to date")

  return true
end

return _M
