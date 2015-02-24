local Object = require "classic"
local utils = require "kong.tools.utils"

-- Constants
local KONG_HOME = os.getenv("KONG_HOME")
if KONG_HOME and KONG_HOME ~= "" then
  KONG_HOME = KONG_HOME.."/"
else
  KONG_HOME = ""
end

local MIGRATION_PATH = KONG_HOME.."database/migrations"

-- Migrations
local Migrations = Object:extend()

function Migrations:new(dao, options)
  self.dao = dao
  self.options = options
  self.migrations_files = utils.retrieve_files(MIGRATION_PATH.."/"..dao.type, '.lua')
end

function Migrations.create(configuration, name, callback)
  for k, _ in pairs(configuration.databases_available) do
    local date_str = os.date("%Y-%m-%d-%H%M%S")
    local file_path = MIGRATION_PATH.."/"..k
    local file_name = date_str.."_"..name
    local interface = [[
local Migration = {
  name = "]]..file_name..[[",

  up = function(options)
    return ]].."[["..[[


    ]].."]]"..[[

  end,

  down = function(options)
    return ]].."[["..[[


    ]].."]]"..[[

  end
}

return Migration
    ]]

    if callback then
      callback(interface, file_path, file_name)
    end
  end
end

function Migrations:migrate(callback)
  for _, migration_file in ipairs(self.migrations_files) do
    local migration_module = loadfile(migration_file)
    if migration_module ~= nil then
      local migration = migration_module()

      -- Generate UP query from string + options
      local up_query = migration.up(self.options)

      local err = self.dao:execute(up_query, true)

      if callback then
        callback(migration, err)
      end
    end
  end
end

function Migrations:rollback(callback)
  local migration_file = self.migrations_files[utils.table_size(self.migrations_files)]
  local migration = loadfile(migration_file)()

  -- Generate DOWN query from string + options
  local down_query = migration.down(self.options)

  local err = self.dao:execute(down_query, true)

  if callback then
    callback(migration, err)
  end
end

function Migrations:reset(callback)
  for _, migration_file in ipairs(utils.reverse_table(self.migrations_files)) do
    local migration = loadfile(migration_file)()

    -- Generate DOWN query from string + options
    local down_query = migration.down(self.options)

    local err = self.dao:execute(down_query, true)

    if callback then
      callback(migration, err)
    end
  end
end

return Migrations
