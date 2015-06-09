local yaml = require "yaml"
local path = require("path").new("/")
local stringy = require "stringy"
local constants = require "kong.constants"

local _M = {}

_M.path = path

function _M.file_exists(path)
  local f, err = io.open(path, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false, err
  end
end

function _M.os_execute(command)
  local n = os.tmpname() -- get a temporary file name to store output
  local exit_code = os.execute("/bin/bash -c '"..command.." > "..n.." 2>&1'")
  local result = _M.read_file(n)
  os.remove(n)

  return string.gsub(result, "[%\r%\n]", ""), exit_code / 256
end

function _M.cmd_exists(cmd)
  local _, code = _M.os_execute("hash "..cmd)
  return code == 0
end

-- Kill a process by PID and wait until it's terminated
-- @param `pid` the pid to kill
function _M.kill_process_by_pid_file(pid_file, signal)
  if _M.file_exists(pid_file) then
    local pid = stringy.strip(_M.read_file(pid_file))
    local res, code = _M.os_execute("while kill -0 "..pid.." >/dev/null 2>&1; do kill "..(signal and "-"..tostring(signal).." " or "")..pid.."; sleep 0.1; done")
    return res, code
  end
end

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
  local file, err = io.open(path, "w")
  if err then
    return false, err
  end

  file:write(value)
  file:close()
  return true
end

function _M.file_size(path)
  local file = io.open(path, "rb")
  local size = file:seek("end")
  file:close()
  return size
end

function _M.retrieve_files(dir, options)
  local fs = require "luarocks.fs"
  local pattern = options.file_pattern
  local exclude_dir_patterns = options.exclude_dir_patterns

  if not pattern then pattern = "" end
  if not exclude_dir_patterns then exclude_dir_patterns = {} end
  local files = {}

  local function tree(dir)
    for _, file in ipairs(fs.list_dir(dir)) do
      local f = path:join(dir, file)
      if fs.is_dir(f) then
        local is_ignored = false
        for _, pattern in ipairs(exclude_dir_patterns) do
          if string.match(f, pattern) then
            is_ignored = true
            break
          end
        end
        if not is_ignored then
          tree(f)
        end
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

  local dao_config = configuration.databases_available[configuration.database]
  if dao_config == nil then
    error("No \""..configuration.database.."\" dao defined")
  end

  -- Adding computed properties to the configuration
  configuration.pid_file = path:join(configuration.nginx_working_dir, constants.CLI.NGINX_PID)

  -- Alias the DAO configuration we are using for this instance for easy access
  configuration.dao_config = dao_config

  -- Load absolute path for the nginx working directory
  if not stringy.startswith(configuration.nginx_working_dir, "/") then
    -- It's a relative path, convert it to absolute
    local fs = require "luarocks.fs"
    configuration.nginx_working_dir = fs.current_dir().."/"..configuration.nginx_working_dir
  end

  -- Instanciate the DAO Factory along with the configuration
  local DaoFactory = require("kong.dao."..configuration.database..".factory")
  local dao_factory = DaoFactory(dao_config.properties, configuration.plugins_available)

  return configuration, dao_factory
end

return _M
