local Object = require "classic"
local IO = require "kong.tools.io"
local stringy = require "stringy"
local utils = require "kong.tools.utils"

local BaseService = Object:extend()

function BaseService.find_cmd(app_name, additional_paths, check_path_func)
  local found_file_paths = {}

  if IO.cmd_exists(app_name) then
    if not check_path_func then
      return app_name
    else
      table.insert(found_file_paths, app_name)
    end
  end

  -- These are some default locations we are always looking into
  local search_dirs = utils.table_merge({
    "/usr/local/sbin",
    "/usr/local/bin",
    "/usr/sbin",
    "/usr/bin",
    "/bin"
  }, additional_paths and additional_paths or {})

  for _, search_dir in ipairs(search_dirs) do
    local file_path = search_dir..(stringy.endswith(search_dir, "/") and "" or "/")..app_name
    if IO.file_exists(file_path) then
      table.insert(found_file_paths, file_path)
    end
  end

  if check_path_func then
    for _, found_file_path in ipairs(found_file_paths) do
      if check_path_func(found_file_path) then
        return found_file_path 
      end
    end
  elseif #found_file_paths > 0 then
    -- Just return the first path
    return found_file_paths[1]
  end

  return nil
end

function BaseService:new(name, nginx_working_dir)
  self._name = name
  self._pid_file_path = nginx_working_dir
                        ..(stringy.endswith(nginx_working_dir, "/") and "" or "/")
                        ..name..".pid"
end

function BaseService:is_running()
  local result = false

  local pid = IO.read_file(self._pid_file_path)
  if pid then
    local _, code = IO.os_execute("kill -0 "..stringy.strip(pid))
    if code and code == 0 then
      result = pid
    end
  end

  return result
end

function BaseService:_get_cmd(additional_paths, check_path_func)
  if not self._cmd then -- Cache the command after the first time
    local cmd = BaseService.find_cmd(self._name, additional_paths, check_path_func)
    if not cmd then
      return nil, "Can't find "..self._name
    end
    self._cmd = cmd
  end
  return self._cmd
end

function BaseService:start()
  -- Returns an error if not implemented
  error("Not implemented")
end

function BaseService:prepare(working_dir)
  -- Create nginx folder if needed
  local _, err = IO.path:mkdir(working_dir)
  if err then
    return false, err
  end
  return true
end

function BaseService:stop(force)
  local pid = self:is_running()
  if pid then
    IO.os_execute("kill "..(force and "-9 " or "")..pid)
    while self:is_running() do
      -- Wait
    end
    if force then
      os.remove(self._pid_file_path) -- Because forcing the kill doesn't kill the PID file
    end
  end
end

return BaseService