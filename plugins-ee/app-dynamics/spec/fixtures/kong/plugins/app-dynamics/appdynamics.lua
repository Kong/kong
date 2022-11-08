-- This module implements a mocked version of the AppDynamics C SDK,
-- as far as it is used in the AppDynamics plugin.  The intent of it
-- is not to completely remodel the behavior of the SDK as we don't
-- completely know what it does.  Instead, we want to ensure that the
-- intended SDK functions are invoked in response to requests sent to
-- Kong.  This is achieved by creating a call trace in a file which
-- can then be asserted against by the integration test for the
-- plugin.

local MOCK_TRACE_FILENAME = os.getenv("KONG_APPD_MOCK_TRACE_FILENAME")

local ffi = require "ffi"
-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

ffi.cdef [[
  char* strdup(const char*);
]]

local function log_call(name, arguments)
  local call_info = name .. "("
  for i = 1,#arguments do
    local argument = arguments[i]
    local formatted_argument
    if type(argument) == 'string' then
      formatted_argument = "\"" .. argument .. "\""
    elseif type(argument) == 'table' then
      formatted_argument = "<" .. tostring(argument) .. ">"
    else
      formatted_argument = tostring(argument)
    end
    call_info = call_info .. formatted_argument
    if i ~= #arguments then
      call_info = call_info .. ", "
    end
  end
  call_info = call_info .. ")\n"
  io.write(call_info)
  if MOCK_TRACE_FILENAME then
    local out = assert(io.open(MOCK_TRACE_FILENAME, "a"))
    out:write(call_info)
    out:close()
  end
end


local appd = {
  APPD_LOG_LEVEL_TRACE = 0,
  APPD_LOG_LEVEL_DEBUG = 1,
  APPD_LOG_LEVEL_INFO = 2,
  APPD_LOG_LEVEL_WARN = 3,
  APPD_LOG_LEVEL_ERROR = 4,
  APPD_LOG_LEVEL_FATAL = 5,

  APPD_LEVEL_NOTICE = 0,
  APPD_LEVEL_WARNING = 1,
  APPD_LEVEL_ERROR = 2,

  appd_config_init = function()
    return {}
  end,

  appd_exitcall_begin = function(bt_handle, backend_name)
    log_call('appd_exitcall_begin', { bt_handle, backend_name })
    return {
      bt_handle = bt_handle,
      backend_name = backend_name,
      correlation_header = bt_handle.correlation_header,
    }
  end,

  appd_exitcall_get_correlation_header = function(exit_handle)
    log_call('appd_exitcall_get_correlation_header', { exit_handle })
    -- The memory allocated by strdup below is never freed.  This
    -- should be acceptable for this mock implementation.
    return ffi.C.strdup(exit_handle.correlation_header)
  end,

  appd_bt_begin = function(name, correlation_header)
    log_call('appd_bt_begin', { name, correlation_header })
    return {
      name = name,
      correlation_header = correlation_header or "mocked-correlation-header-content",
    }
  end,
}

setmetatable(
  appd,
  {
    __index = function(_, name)
      return function(...)
        log_call(name, {...})
        return 0                                            -- 0 generally indicates success in the AppDynamics SDK
      end
    end
  }
)

return appd
