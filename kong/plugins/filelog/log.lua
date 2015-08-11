-- Copyright (C) Mashape, Inc.

local ffi = require "ffi"
local bit = require "bit"
local cjson = require "cjson"
local fd_util = require "kong.plugins.filelog.fd_util"
local basic_serializer = require "kong.plugins.log_serializers.basic"

ffi.cdef[[
int open(char * filename, int flags, int mode);
int write(int fd, void * ptr, int numbytes);
]]

local octal = function(n) return tonumber(n, 8) end

local O_CREAT = octal('0100')
local O_APPEND = octal('02000')
local O_WRONLY = octal('0001')

local S_IWUSR = octal('00200')
local S_IRUSR = octal('00400')
local S_IXUSR = octal('00100')

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
    fd = ffi.C.open(string_to_char(conf.path), bit.bor(O_CREAT, O_APPEND, O_WRONLY), bit.bor(S_IWUSR, S_IRUSR, S_IXUSR))
    fd_util.set_fd(conf.path, fd)
  end

  ffi.C.write(fd, string_to_char(message), string.len(message))
end

local _M = {}

function _M.execute(conf)
  local message = basic_serializer.serialize(ngx)

  local ok, err = ngx.timer.at(0, log, conf, message)
  if not ok then
    ngx.log(ngx.ERR, "[filelog] failed to create timer: ", err)
  end
end

return _M
