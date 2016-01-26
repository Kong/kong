local BaseModel = require "kong.dao.base_model"
local Object = require "classic"

local CORE_MODELS = {"apis"}
local _db

local Factory = Object:extend()

function Factory:__index(key)
  local models = rawget(self, "models")
  if models and models[key] then
    return models[key]
  else
    return Factory[key]
  end
end

function Factory:new(db_type, options)
  self.db_type = db_type
  self.models = {}

  local DB = require("kong.dao."..db_type.."_db")
  _db = DB(options)

  -- Create models and give them the db instance
  for _, m_name in ipairs(CORE_MODELS) do
    local m_schema = require("kong.dao.schemas."..m_name)
    local model = BaseModel(_db, m_schema)
    self.models[m_name] = model
  end
end

-- Migrations

function Factory:drop_schema()
  for _, model in ipairs(self.models) do
    local err = _db:drop_table(model.table)
    if err then
      error(err)
    end
  end

  local err = _db:drop_table("schema_migrations")
  if err then
    error(err)
  end
end

function Factory:migrations_modules()
  local core_migrations = require("kong.dao.migrations."..self.db_type)
  return {
    core = core_migrations
  }
end

function Factory:current_migrations()
  return _db:current_migrations()
end

function Factory:run_migrations()
  local migrations_modules = self:migrations_modules()
  local cur_migrations, err = self:current_migrations()
  if err then
    return false, err
  end

  for identifier, migrations in pairs(migrations_modules) do
    for _, migration in ipairs(migrations) do
      local mig_type = type(migration.up)
      if mig_type == "string" then
        -- exec string migration
        err = select(2, _db:query(migration.up))
        if err then
          return false, string.format("Error during migration %s: %s", migration.name, err)
        end
      end

      -- record success
      err = _db:record_migration(identifier, migration.name)
      if err then
        return false, string.format("Error recording migration %s: %s", migration.name, err)
      end
    end
  end

  return true
end

return Factory
