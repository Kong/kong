-- Copyright (C) Mashape, Inc.

local ffi = require "ffi"
local cjson = require "cjson"
local fd_util = require "kong.plugins.filelog.fd_util"
local basic_serializer = require "kong.plugins.log_serializers.basic"

ffi.cdef[[
typedef struct {
  char *fpos;
  void *base;
  unsigned short handle;
  short flags;
  short unget;
  unsigned long alloc;
  unsigned short buffincrement;
} FILE;

FILE *fopen(const char *filename, const char *mode);
int fflush(FILE *stream);
int fprintf(FILE *stream, const char *format, ...);
]]

-- Log to a file
-- @param `premature`
-- @param `conf`     Configuration table, holds http endpoint details
-- @param `message`  Message to be logged
local function log(premature, conf, message)
  message = cjson.encode(message).."\n"

  local f = fd_util.get_fd(conf.path)
  if not f then
    f = ffi.C.fopen(conf.path, "a")
    fd_util.set_fd(conf.path, f)
  end

  ffi.C.fprintf(f, message)
  ffi.C.fflush(f)
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
