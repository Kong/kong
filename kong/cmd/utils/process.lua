local read_file = require("pl.file").read
local resty_kill = require("resty.signal").kill

local tonumber = tonumber
local type = type
local floor = math.floor


-- not supporting other usage of kill(2) for the moment
local MIN_PID = 1

-- source: proc(5) man page
local MAX_PID = 2 ^ 22


local SIG_NONE   = 0
local SIG_HUP    = 1
local SIG_INT    = 2
local SIG_QUIT   = 3
local SIG_ILL    = 4
local SIG_TRAP   = 5
local SIG_ABRT   = 6
local SIG_BUS    = 7
local SIG_FPE    = 8
local SIG_KILL   = 9
local SIG_USR1   = 10
local SIG_SEGV   = 11
local SIG_USR2   = 12
local SIG_PIPE   = 13
local SIG_ALRM   = 14
local SIG_TERM   = 15
local SIG_CHLD   = 17
local SIG_CONT   = 18
local SIG_STOP   = 19
local SIG_TSTP   = 20
local SIG_TTIN   = 21
local SIG_TTOU   = 22
local SIG_URG    = 23
local SIG_XCPU   = 24
local SIG_XFSZ   = 25
local SIG_VTALRM = 26
local SIG_PROF   = 27
local SIG_WINCH  = 28
local SIG_IO     = 29
local SIG_PWR    = 30
local SIG_EMT    = 31
local SIG_SYS    = 32
local SIG_INFO   = 33


---
-- Checks if a value is a valid PID and returns it.
--
---```lua
---  validate_pid(123)   --> 123
---
---  -- value can be a numeric string
---  validate_pid("123") --> 123
---  validate_pid("foo") --> nil
---
---  -- value must be an integer
---  validate_pid(1.23)  --> nil
---
---  -- value must be in the valid range for PIDs
---  validate_pid(0)     --> nil
---  validate_pid(2^32)  --> nil
---```
---
---@param  value    any
---@return integer? pid
local function validate_pid(value)
  local pid = tonumber(value)
  return pid
         -- good enough integer check for our use case
         and floor(pid) == pid
         and pid >= MIN_PID and pid <= MAX_PID
         and pid
end


---
-- Read and return the process ID from a pid file.
--
---@param  fname       string
---@return integer|nil pid
---@return nil|string  error
local function pid_from_file(fname)
  local data, err = read_file(fname)
  if not data then
    return nil, "failed reading PID file: " .. tostring(err)
  end

  -- strip whitespace
  data = data:gsub("^%s*(.-)%s*$", "%1")

  if #data == 0 then
    return nil, "PID file is empty"
  end

  local pid = validate_pid(data)

  if not pid then
    return nil, "file does not contain a valid PID"
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
-- Detects a PID from input and returns it as a number.
--
-- The target process may be supplied as a PID (number) or path to a
-- pidfile (string).
--
-- On success, returns the PID as a number.
--
-- On any failure related to reading/parsing the PID from a file, returns
-- `nil` and an error string.
--
-- Raises an error for invalid input (wrong Lua type, target is not a valid PID
-- number, etc).
--
---@param  target      kong.cmd.utils.process.target
---@return integer|nil pid
---@return nil|string  error
local function get_pid(target)
  local typ = type(target)

  if typ == "number" then
    if not validate_pid(target) then
      error("target PID must be an integer from "
            .. MIN_PID .. " to " .. MAX_PID
            .. ", got: " .. tostring(target), 2)
    end

    return target

  elseif typ == "string" then
    return pid_from_file(target)

  else
    error("invalid PID type: '" .. typ .. "'", 2)
  end
end


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
  local pid, err = get_pid(target)

  if not pid then
    return nil, err
  end

  return resty_kill(pid, sig)
end


---
-- Send the TERM signal to a process.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil ok
---@return nil|string  error
local function term(target)
  return signal(target, SIG_TERM)
end


---
-- Send the KILL signal to a process.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil ok
---@return nil|string  error
local function kill(target)
  return signal(target, SIG_KILL)
end


---
-- Send the QUIT signal to a process.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil ok
---@return nil|string  error
local function quit(target)
  return signal(target, SIG_QUIT)
end


---
-- Send the HUP signal to a process.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil ok
---@return nil|string  error
local function hup(target)
  return signal(target, SIG_HUP)
end


---
-- Check for the existence of a process.
--
-- Under the hood this sends the special `0` signal to check the process state.
--
-- Returns a boolean if the process unequivocally exists/does not exist.
--
-- Returns `nil` and an error string if an error is encountered while attemping
-- to read a pidfile.
--
-- Raises an error for invalid input or upon any unexpected result returned by
-- resty.signal.
--
--
-- Callers should decide for themselves how strict they must be when handling
-- errors. For instance, when NGINX is starting up there is a period where the
-- pidfile may be empty or non-existent, which will result in this function
-- returning nil+error. For some callers this might be expected and acceptible,
-- but for others it may not.
--
---@param  target      kong.cmd.utils.process.target
---@return boolean|nil exists
---@return nil|string  error
local function exists(target)
  local pid, err = get_pid(target)
  if not pid then
    return nil, err
  end

  local ok
  ok, err = resty_kill(pid, 0)

  if ok then
    return true

  elseif err == "No such process" then
    return false

  elseif err == "Operation not permitted" then
    -- the process *does* exist but is not manageable by us
    return true
  end

  error(err or "unexpected error from resty.signal.kill()")
end


return {
  exists = exists,
  pid_from_file = pid_from_file,
  signal = signal,
  pid = get_pid,

  term = term,
  kill = kill,
  quit = quit,
  hup = hup,

  SIG_NONE   = SIG_NONE,
  SIG_HUP    = SIG_HUP,
  SIG_INT    = SIG_INT,
  SIG_QUIT   = SIG_QUIT,
  SIG_ILL    = SIG_ILL,
  SIG_TRAP   = SIG_TRAP,
  SIG_ABRT   = SIG_ABRT,
  SIG_BUS    = SIG_BUS,
  SIG_FPE    = SIG_FPE,
  SIG_KILL   = SIG_KILL,
  SIG_USR1   = SIG_USR1,
  SIG_SEGV   = SIG_SEGV,
  SIG_USR2   = SIG_USR2,
  SIG_PIPE   = SIG_PIPE,
  SIG_ALRM   = SIG_ALRM,
  SIG_TERM   = SIG_TERM,
  SIG_CHLD   = SIG_CHLD,
  SIG_CONT   = SIG_CONT,
  SIG_STOP   = SIG_STOP,
  SIG_TSTP   = SIG_TSTP,
  SIG_TTIN   = SIG_TTIN,
  SIG_TTOU   = SIG_TTOU,
  SIG_URG    = SIG_URG,
  SIG_XCPU   = SIG_XCPU,
  SIG_XFSZ   = SIG_XFSZ,
  SIG_VTALRM = SIG_VTALRM,
  SIG_PROF   = SIG_PROF,
  SIG_WINCH  = SIG_WINCH,
  SIG_IO     = SIG_IO,
  SIG_PWR    = SIG_PWR,
  SIG_EMT    = SIG_EMT,
  SIG_SYS    = SIG_SYS,
  SIG_INFO   = SIG_INFO,
}
