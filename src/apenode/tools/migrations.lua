local Object = require "classic"
local utils = require "apenode.tools.utils"

-- Constants
local kMigrationsPath = "database/migrations"

-- Migrations
local Migrations = Object:extend()

function Migrations:new(dao)
  self.dao = dao
  self.migrations_files = utils.retrieve_files(kMigrationsPath.."/"..dao.type, '.lua')
end

function Migrations.create(configuration, name, callback)
  for k,_ in pairs(configuration.databases_available) do
    local date_str = os.date("%Y-%m-%d-%H%M%S")
    local file_path = kMigrationsPath.."/"..k
    local file_name = date_str.."_"..name
    local interface = [[
local Migration = {
  name = "]]..file_name..[[",

  up = ]].."[["..[[


  ]].."]]"..[[,

  down = ]].."[["..[[


  ]].."]]"..[[

}

return Migration
  ]]

    if callback then
      callback(interface, file_path, file_name)
    end
  end
end

function Migrations:migrate(callback)
  for _,migration_file in ipairs(self.migrations_files) do
    local migration_module = loadfile(migration_file)
    if migration_module ~= nil then
      local migration = migration_module()

      self.dao:execute(migration.up)

      if callback then
        callback(migration)
      end
    end
  end
end

function Migrations:rollback(callback)
  local migration_file = self.migrations_files[utils.table_size(self.migrations_files)]
  local migration = loadfile(migration_file)()

  self.dao:execute(migration.down)

  if callback then
    callback(migration)
  end
end

function Migrations:reset(callback)
  for _,migration_file in ipairs(utils.reverse_table(self.migrations_files)) do
    local migration = loadfile(migration_file)()

    self.dao:execute(migration.down)

    if callback then
      callback(migration)
    end
  end
end

return Migrations
