local _M = {}

local timing


local function before_connect_new(self, options)
  local destination
  local scheme = options.scheme
  if scheme == nil then
    destination = "unix://" .. options.path

  else
    local port = options.port or (scheme == "http" and 80 or 443)
    destination = scheme .. "://" .. options.host .. ":" .. port
  end

  self.__kong_timing_destination__ = destination

  timing.enter_context("external_http")
  timing.enter_context(destination)
end


-- https://github.com/ledgetech/lua-resty-http#TCP-only-connect
local function before_connect_deprecated(self, host, port, _options)
  local destination
  if type(port) == "number" then
    destination = "http(s)://" .. host .. ":" .. port

  else
    destination = "unix://" .. host
  end

  self.__kong_timing_destination__ = destination

  timing.enter_context("external_http")
  timing.enter_context(destination)
end


local function before_connect(self, arg0, ...)
  if type(arg0) == "table" then
    before_connect_new(self, arg0)
    return
  end

  before_connect_deprecated(self, arg0, ...)
end


local function after_connect()
  timing.leave_context() -- leave destination
  timing.leave_context() -- leave external_http
end


local function before_request(self, _params)
  timing.enter_context("external_http")
  timing.enter_context(self.__kong_timing_destination__ or "unknown")
  timing.enter_context("http_request")
end


local function after_request()
  timing.leave_context() -- leave http_request
  timing.leave_context() -- leave destination
  timing.leave_context() -- leave external_http
end


function _M.register_hooks(timing_module)
  local http = require("resty.http")
  local req_dyn_hook = require("kong.dynamic_hook")

  --[[
    The `connect()` function can receive <= 4 arguments (including `self`).
    
    The `before_connect_deprecated()` is the deprecated version of `connect()`,
    it can receive 4 arguments (including `self`).

    The `connect()` function can receive 2 arguments (including `self`).

    So the max_args is 4.
  --]]
  req_dyn_hook.hook_function("timing", http, "connect", 4, {
    befores = { before_connect },
    afters = { after_connect },
  })

  --[[
    The `request()` function can receive <= 2 arguments (including `self`).
    Here is the signature of the `request()` function:
    function request(self, params)
  --]]
  req_dyn_hook.hook_function("timing", http, "request", 2, {
    befores = { before_request },
    afters = { after_request },
  })

  timing = timing_module
end


return _M
