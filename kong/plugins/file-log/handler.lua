-- Copyright (C) Kong Inc.
local ffi = require "ffi"
local cjson = require "cjson"
local system_constants = require "lua_system_constants"
local basic_serializer = require "kong.plugins.log-serializers.basic"
local BasePlugin = require "kong.plugins.base_plugin"

local ngx_timer = ngx.timer.at
local O_CREAT = system_constants.O_CREAT()
local O_WRONLY = system_constants.O_WRONLY()
local O_APPEND = system_constants.O_APPEND()
local S_IRUSR = system_constants.S_IRUSR()
local S_IWUSR = system_constants.S_IWUSR()
local S_IRGRP = system_constants.S_IRGRP()
local S_IROTH = system_constants.S_IROTH()

local oflags = bit.bor(O_WRONLY, O_CREAT, O_APPEND)
local mode = bit.bor(S_IRUSR, S_IWUSR, S_IRGRP, S_IROTH)

ffi.cdef[[
int write(int fd, const void * ptr, int numbytes);
]]

-- fd tracking utility functions
local file_descriptors = {}

local LOG_LEVELS = {
  debug = 7,
  info = 6,
  notice = 5,
  warning = 4,
  err = 3,
  crit = 2,
  alert = 1,
  emerg = 0
}

-- Log to a file. Function used as callback from an nginx timer.
-- @param `premature` see OpenResty `ngx.timer.at()`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  if premature then
    return
  end

  local msg = cjson.encode(message) .. "\n"

  local fd = file_descriptors[conf.path]

  if fd and conf.reopen then
    -- close fd, we do this here, to make sure a previously cached fd also
    -- gets closed upon dynamic changes of the configuration
    ffi.C.close(fd)
    file_descriptors[conf.path] = nil
    fd = nil
  end

  if not fd then
    fd = ffi.C.open(conf.path, oflags, mode)
    if fd < 0 then
      local errno = ffi.errno()
      ngx.log(ngx.ERR, "[file-log] failed to open the file: ", ffi.string(ffi.C.strerror(errno)))
    else
      file_descriptors[conf.path] = fd
    end
  end

  local severity
  if message.response.status >= 500 then
    severity = conf.server_errors_severity
  elseif message.response.status >= 400 then
    severity = conf.client_errors_severity
  else
    severity = conf.successful_severity
  end

  if LOG_LEVELS[severity] <= LOG_LEVELS[conf.log_level] then
    ffi.C.write(fd, msg, #msg)
  end
end

local FileLogHandler = BasePlugin:extend()

FileLogHandler.PRIORITY = 9
FileLogHandler.VERSION = "0.1.0"

function FileLogHandler:new()
  FileLogHandler.super.new(self, "file-log")
end

function FileLogHandler:log(conf)
  FileLogHandler.super.log(self)
  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx_timer(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[file-log] failed to create timer: ", err)
  end

end

return FileLogHandler
