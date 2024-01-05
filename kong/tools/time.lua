local ffi = require "ffi"


local C             = ffi.C
local tonumber      = tonumber


ffi.cdef[[
typedef long time_t;
typedef int clockid_t;
typedef struct timespec {
        time_t   tv_sec;        /* seconds */
        long     tv_nsec;       /* nanoseconds */
} nanotime;

int clock_gettime(clockid_t clk_id, struct timespec *tp);
]]


local _M = {}


do
  local NGX_ERROR = ngx.ERROR

  if not pcall(ffi.typeof, "ngx_uint_t") then
    ffi.cdef [[
      typedef uintptr_t ngx_uint_t;
    ]]
  end

  if not pcall(ffi.typeof, "ngx_int_t") then
    ffi.cdef [[
      typedef intptr_t ngx_int_t;
    ]]
  end

  -- ngx_str_t defined by lua-resty-core
  local s = ffi.new("ngx_str_t[1]")
  s[0].data = "10"
  s[0].len = 2

  if not pcall(function() C.ngx_parse_time(s, 0) end) then
    ffi.cdef [[
      ngx_int_t ngx_parse_time(ngx_str_t *line, ngx_uint_t is_sec);
    ]]
  end

  function _M.nginx_conf_time_to_seconds(str)
    s[0].data = str
    s[0].len = #str

    local ret = C.ngx_parse_time(s, 1)
    if ret == NGX_ERROR then
      error("bad argument #1 'str'", 2)
    end

    return tonumber(ret, 10)
  end
end


do
  local nanop = ffi.new("nanotime[1]")
  function _M.time_ns()
    -- CLOCK_REALTIME -> 0
    C.clock_gettime(0, nanop)
    local t = nanop[0]

    return tonumber(t.tv_sec) * 1e9 + tonumber(t.tv_nsec)
  end
end


do
  local now             = ngx.now
  local update_time     = ngx.update_time
  local start_time      = ngx.req.start_time
  local monotonic_msec  = require("resty.core.time").monotonic_msec

  function _M.get_now_ms()
    return now() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function _M.get_updated_now_ms()
    update_time()
    return now() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function _M.get_start_time_ms()
    return start_time() * 1000 -- time is kept in seconds with millisecond resolution.
  end

  function _M.get_updated_monotonic_ms()
    update_time()
    return monotonic_msec()
  end
end


return _M
