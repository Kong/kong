local DAO = require "kong.dao.dao"
local Object = require "classic"
local ModelFactory = require "kong.dao.model_factory"

local CORE_MODELS = {"apis", "consumers", "plugins"}
local _db

local Factory = Object:extend()

function Factory:__index(key)
  local daos = rawget(self, "daos")
  if daos and daos[key] then
    return daos[key]
  else
    return Factory[key]
  end
end

function Factory:new(db_type, options)
  self.db_type = db_type
  self.daos = {}

  local DB = require("kong.dao."..db_type.."_db")
  _db = DB(options)

  -- Create daos and give them the db instance
  for _, m_name in ipairs(CORE_MODELS) do
    local m_schema = require("kong.dao.schemas."..m_name)
    local model_mt = ModelFactory(m_schema)
    local dao = DAO(_db, model_mt, m_schema.table)
    self.daos[m_name] = dao
  end
end

-- Migrations

function Factory:drop_schema()
  for _, dao in pairs(self.daos) do
    _db:drop_table(dao.table)
  end

  _db:drop_table("schema_migrations")
end

function Factory:truncate_tables()
  for _, dao in pairs(self.daos) do
    local err = _db:truncate_table(dao.table)
    if err then
      error(err)
    end
  end
end

function Factory:migrations_modules()
  local core_migrations = require("kong.dao.migrations."..self.db_type)
  return {
    core = core_migrations
  }
end

function Factory:current_migrations()
  local rows, err = _db:current_migrations()
  if err then
    return nil, err
  end

  local cur_migrations = {}
  for _, row in ipairs(rows) do
    cur_migrations[row.id] = row.migrations
  end
  return cur_migrations
end

function Factory:run_migrations(on_migrate, on_success)
  local migrations_modules = self:migrations_modules()
  local cur_migrations, err = self:current_migrations()
  if err then
    return false, err
  end

  for identifier, migrations in pairs(migrations_modules) do
    local recorded = cur_migrations[identifier] or {}
    local to_run = {}
    for i, mig in ipairs(migrations) do
      if mig.name ~= recorded[i] then
        to_run[#to_run + 1] = mig
      end
    end

    if #to_run > 0 and on_migrate ~= nil then
      -- we have some migrations to run
      on_migrate(identifier)
    end

    for _, migration in ipairs(to_run) do
      local mig_type = type(migration.up)
      if mig_type == "string" then
        -- exec string migration
        err = _db:queries(migration.up)
        if err then
          return false, string.format("Error during migration %s: %s", migration.name, err)
        end
      end

      -- record success
      err = _db:record_migration(identifier, migration.name)
      if err then
        return false, string.format("Error recording migration %s: %s", migration.name, err)
      end

      if on_success ~= nil then
        on_success(identifier, migration.name)
      end
    end
  end

  return true
end

return Factory
