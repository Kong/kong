-- Copyright (C) Mashape, Inc.

local ffi = require "ffi"
local cjson = require "cjson"
local fd_util = require "kong.plugins.file-log.fd_util"
local system_constants = require "lua_system_constants"
local basic_serializer = require "kong.plugins.log-serializers.basic"

ffi.cdef[[
int open(char * filename, int flags, int mode);
int write(int fd, void * ptr, int numbytes);

char *strerror(int errnum);
]]

local function string_to_char(str)
  return ffi.cast("uint8_t*", str)
end

-- Log to a file
-- @param `premature`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  message = cjson.encode(message).."\n"

  local fd = fd_util.get_fd(conf.path)
  if not fd then
    fd = ffi.C.open(string_to_char(conf.path), 
                    bit.bor(system_constants.O_WRONLY(), system_constants.O_CREAT(), system_constants.O_APPEND()), 
                    bit.bor(system_constants.S_IWUSR(), system_constants.S_IRUSR(), system_constants.S_IXUSR()))
    if fd < 0 then
      local errno = ffi.errno()
      ngx.log(ngx.ERR, "[file-log] failed to open the file: ", ffi.string(ffi.C.strerror(errno)))
    else
      fd_util.set_fd(conf.path, fd)
    end
  end

  ffi.C.write(fd, string_to_char(message), string.len(message))
end

local _M = {}

function _M.execute(conf)
  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx.timer.at(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[file-log] failed to create timer: ", err)
  end
end

return _M
