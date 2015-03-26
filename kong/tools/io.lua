local constants = require "kong.constants"
local path = require("path").new("/")
local yaml = require "yaml"

local _M = {}

_M.path = path

function _M.read_file(path)
  local contents = nil
  local file = io.open(path, "rb")
  if file then
    contents = file:read("*all")
    file:close()
  end
  return contents
end

function _M.write_to_file(path, value)
  local file = io.open(path, "w")
  file:write(value)
  file:close()
end

function _M.file_exists(name)
  local f = io.open(name, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

function _M.retrieve_files(dir, options)
  local fs = require "luarocks.fs"
  local pattern = options.file_pattern
  local exclude_dir_pattern = options.exclude_dir_pattern

  if not pattern then pattern = "" end
  if not exclude_dir_pattern then exclude_dir_pattern = "" end
  local files = {}

  local function tree(dir)
    for _, file in ipairs(fs.list_dir(dir)) do
      local f = path:join(dir, file)
      if fs.is_dir(f) and string.match(f, exclude_dir_pattern) == nil then
        tree(f)
      elseif fs.is_file(f) and string.match(file, pattern) ~= nil then
        table.insert(files, f)
      end
    end
  end

  tree(dir)

  return files
end

function _M.load_configuration_and_dao(configuration_path)
  local configuration_file = _M.read_file(configuration_path)
  if not configuration_file then
    error("No configuration file at: "..configuration_path)
  end

  -- Configuraiton should already be validated by the CLI at this point
  local configuration = yaml.load(configuration_file)

  local dao_properties = configuration.databases_available[configuration.database]
  if dao_properties == nil then
    error("No dao \""..configuration.database.."\" defined")
  end

  -- Adding computed properties to the configuration
  configuration.pid_file = path:join(configuration.nginx_working_dir, constants.CLI.NGINX_PID)

  -- Instanciate the DAO Factory along with the configuration
  local DaoFactory = require("kong.dao."..configuration.database..".factory")
  local dao_factory = DaoFactory(dao_properties.properties, configuration.plugins_available)

  return configuration, dao_factory
end


return _M
