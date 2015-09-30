---
-- IO related utility functions
--

local yaml = require "yaml"
local path = require("path").new("/")
local stringy = require "stringy"
local constants = require "kong.constants"

local _M = {}

_M.path = path

---
-- Checks existence of a file.
-- @param path path/file to check
-- @return `true` if found, `false` + error message otherwise
function _M.file_exists(path)
  local f, err = io.open(path, "r")
  if f ~= nil then
    io.close(f)
    return true
  else
    return false, err
  end
end

---
-- Execute an OS command and catch the output.
-- @param command OS command to execute
-- @return string containing command output (both stdout and stderr)
-- @return exitcode
function _M.os_execute(command)
  local n = os.tmpname() -- get a temporary file name to store output
  local f = os.tmpname() -- get a temporary file name to store script
  _M.write_to_file(f, command)
  local exit_code = os.execute("/bin/bash "..f.." > "..n.." 2>&1")
  local result = _M.read_file(n)
  os.remove(n)
  os.remove(f)
  return string.gsub(string.gsub(result, "^"..f..":[%s%w]+:%s*", ""), "[%\r%\n]", ""), exit_code / 256
end

---
-- Check existence of a command.
-- @param cmd command being searched for
-- @return `true` of found, `false` otherwise
function _M.cmd_exists(cmd)
  local _, code = _M.os_execute("hash "..cmd)
  return code == 0
end

--- Kill a process by PID.
-- Kills the process and waits until it's terminated
-- @param pid_file the file containing the pid to kill
-- @param signal the signal to use
-- @return `os_execute` results, see os_execute.
function _M.kill_process_by_pid_file(pid_file, signal)
  if _M.file_exists(pid_file) then
    local pid = stringy.strip(_M.read_file(pid_file))
    return _M.os_execute("while kill -0 "..pid.." >/dev/null 2>&1; do kill "..(signal and "-"..tostring(signal).." " or "")..pid.."; sleep 0.1; done")
  end
end

--- Read file contents.
-- @param path filepath to read
-- @return file contents as string, or `nil` if not succesful
function _M.read_file(path)
  local contents = nil
  local file = io.open(path, "rb")
  if file then
    contents = file:read("*all")
    file:close()
  end
  return contents
end

--- Write file contents.
-- @param path filepath to write to
-- @return `true` upon success, or `false` + error message on failure
function _M.write_to_file(path, value)
  local file, err = io.open(path, "w")
  if err then
    return false, err
  end

  file:write(value)
  file:close()
  return true
end

--- Get the filesize.
-- @param path path to file to check
-- @return size of file, or `nil` on failure
function _M.file_size(path)
  local size
  local file = io.open(path, "rb")
  if file then
    size = file:seek("end")
    file:close()
  end
  return size
end

--- Load a yaml configuration file.
-- The return config will get 2 extra fields; `pid_file` of the nginx process
-- and `dao_config` as a shortcut to the dao configuration
-- @param configuration_path path to configuration file to load
-- @return config Loaded configuration table
-- @return dao_factory the accompanying DAO factory
function _M.load_configuration_and_dao(configuration_path)
  local configuration_file = _M.read_file(configuration_path)
  if not configuration_file then
    error("No configuration file at: "..configuration_path)
  end

  -- Configuration should already be validated by the CLI at this point
  local configuration = yaml.load(configuration_file)

  local dao_config = configuration.databases_available[configuration.database]
  if dao_config == nil then
    error('No "'..configuration.database..'" dao defined')
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

  -- Instantiate the DAO Factory along with the configuration
  local DaoFactory = require("kong.dao."..configuration.database..".factory")
  local dao_factory = DaoFactory(dao_config.properties, configuration.plugins_available)

  return configuration, dao_factory
end

return _M
