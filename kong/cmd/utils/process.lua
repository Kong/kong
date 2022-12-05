local read_file = require("pl.file").read
local kill = require("resty.signal").kill

local tonumber = tonumber
local type = type


---
-- Read and return the process ID from a pid file.
--
---@param  fname       string
---@return integer|nil pid
---@return nil|string  error
local function pid_from_file(fname)
  local data, err = read_file(fname)
  if not data then
    return nil, err
  end

  -- strip whitespace
  data = data:gsub("^%s*(.-)%s*$", "%1")

  if #data == 0 then
    return nil, "pid file is empty"
  end

  local pid = tonumber(data)
  if not pid then
    return nil, "file does not contain a pid: " .. data
  end

  return pid
end


---
-- Detects a PID from input and returns it as a number.
--
---@param  target      string|number
---@return integer|nil pid
---@return nil|string  error
local function guess_pid(target)
  local typ = type(target)

  local pid, err

  if typ == "number" then
    pid = target

  elseif typ == "string" then
    -- for the sake of compatibility we're going to accept PID input as a
    -- numeric string, but this is potentially ambiguous with a PID file,
    -- so we'll try to load from a file first before attempting to treat
    -- the input as a numeric string
    pid, err = pid_from_file(target)

    -- PID was supplied as a string (i.e. "123")
    if not pid then
      pid = tonumber(target)
    end

  else
    error("invalid PID target type: " .. typ, 2)
  end

  if not pid then
    return nil, err

  elseif pid < 1 then
    error("pid must be >= 1", 2)
  end

  return pid
end


---
-- Target processes may be referenced by their integer id (PID)
-- or by a pid filename.
--
---@alias kong.cmd.utils.process.target
---| integer # pid
---| string  # pid file


---
-- Send a signal to a process.
--
-- The signal may be specified as a name ("TERM") or integer (15).
--
---@param  target      kong.cmd.utils.process.target
---@param  sig         resty.signal.name|integer
---@return boolean|nil ok
---@return nil|string  error
local function signal(target, sig)
  local pid, err = guess_pid(target)

  if not pid then
    return nil, err
  end

  return kill(pid, sig)
end


---
-- Check for the existence of a process.
--
-- Under the hood this sends the special `0` signal to check the process state.
--
-- Returns true|false under normal circumstances or nil and an error string if
-- an error occurs.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil exists
---@return nil|string  error
local function exists(target)
  local ok, err = signal(target, "NONE")

  if ok then
    return true

  elseif err == "No such process" then
    return false
  end

  return ok, err
end


return {
  exists = exists,
  pid_from_file = pid_from_file,
  signal = signal,
  guess_pid = guess_pid,
}
