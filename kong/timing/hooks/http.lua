local _M = {}

local timing


local function before_connect_new(self, options)
  local destination
  if options.scheme == nil then
    destination = "unix://" .. options.path

  else
    local port = options.port or (options.scheme == "http" and 80 or 443)
    destination = options.scheme .. "://" .. options.host .. ":" .. port
  end

  self.__kong_timing_destination__ = destination

  timing.enter_context("external_http")
  timing.enter_context(destination)
end


local function before_connect_deprecated(self, host, port, _options)
  local destination
  if type(port) == "number" then
    destination = "http(s)://" .. host .. ":" .. tostring(port)

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

  req_dyn_hook.hook_function("timing", http, "connect", 4, {
    befores = { before_connect },
    afters = { after_connect },
  })

  req_dyn_hook.hook_function("timing", http, "request", 2, {
    befores = { before_request },
    afters = { after_request },
  })

  timing = timing_module
end


return _M
