---
-- Manipulation of the response from the Service
-- @module kong.service.response

local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local sub = string.sub
local fmt = string.format
local gsub = string.gsub
local type = type
local error = error
local lower = string.lower
local tonumber = tonumber
local getmetatable = getmetatable
local setmetatable = setmetatable
local check_phase = phase_checker.check


local PHASES = phase_checker.phases


local header_body_log = phase_checker.new(PHASES.header_filter,
                                          PHASES.body_filter,
                                          PHASES.log)


local attach_resp_headers_mt


do
  local resp_headers_orig_mt_index


  local resp_headers_mt = {
    __index = function(t, name)
      if type(name) == "string" then
        local var = fmt("upstream_http_%s", gsub(lower(name), "-", "_"))
        if not ngx.var[var] then
          return nil
        end
      end

      return resp_headers_orig_mt_index(t, name)
    end,
  }


  attach_resp_headers_mt = function(response_headers, err)
    if not resp_headers_orig_mt_index then
      local mt = getmetatable(response_headers)
      resp_headers_orig_mt_index = mt.__index
    end

    setmetatable(response_headers, resp_headers_mt)

    return response_headers, err
  end
end


local function new(pdk, major_version)
  local response = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000


  ---
  -- Returns the HTTP status code of the response from the Service as a Lua number.
  --
  -- @function kong.service.response.get_status
  -- @phases `header_filter`, `body_filter`, `log`
  -- @treturn number|nil the status code from the response from the Service, or `nil`
  -- if the request was not proxied (i.e. `kong.response.get_source()` returned
  -- anything other than `"service"`.
  -- @usage
  -- kong.log.inspect(kong.service.response.get_status()) -- 418
  function response.get_status()
    check_phase(header_body_log)

    return tonumber(sub(ngx.var.upstream_status or "", -3))
  end


  ---
  -- Returns a Lua table holding the headers from the response from the Service. Keys are
  -- header names. Values are either a string with the header value, or an array of
  -- strings if a header was sent multiple times. Header names in this table are
  -- case-insensitive and dashes (`-`) can be written as underscores (`_`); that is,
  -- the header `X-Custom-Header` can also be retrieved as `x_custom_header`.
  --
  -- Unlike `kong.response.get_headers()`, this function will only return headers that
  -- were present in the response from the Service (ignoring headers added by Kong itself).
  -- If the request was not proxied to a Service (e.g. an authentication plugin rejected
  -- a request and produced an HTTP 401 response), then the returned `headers` value
  -- might be `nil`, since no response from the Service has been received.
  --
  -- By default, this function returns up to **100** headers. The optional
  -- `max_headers` argument can be specified to customize this limit, but must be
  -- greater than **1** and not greater than **1000**.
  -- @function kong.service.response.get_headers
  -- @phases `header_filter`, `body_filter`, `log`
  -- @tparam[opt] number max_headers customize the headers to parse
  -- @treturn table the response headers in table form
  -- @treturn string err If more headers than `max_headers` were present, a
  -- string with the error `"truncated"`.
  -- @usage
  -- -- Given a response with the following headers:
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  -- local headers = kong.service.response.get_headers()
  -- if headers then
  --   kong.log.inspect(headers.x_custom_header) -- "bla"
  --   kong.log.inspect(headers.x_another[1])    -- "foo bar"
  --   kong.log.inspect(headers["X-Another"][2]) -- "baz"
  -- end
  function response.get_headers(max_headers)
    check_phase(header_body_log)

    if max_headers == nil then
      return attach_resp_headers_mt(ngx.resp.get_headers(MAX_HEADERS_DEFAULT))
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return attach_resp_headers_mt(ngx.resp.get_headers(max_headers))
  end

  ---
  -- Returns the value of the specified response header.
  --
  -- Unlike `kong.response.get_header()`, this function will only return a header
  -- if it was present in the response from the Service (ignoring headers added by Kong
  -- itself).
  --
  -- @function kong.service.response.get_header
  -- @phases `header_filter`, `body_filter`, `log`
  -- @tparam string name The name of the header.
  --
  -- Header names in are case-insensitive and are normalized to lowercase, and
  -- dashes (`-`) can be written as underscores (`_`); that is, the header
  -- `X-Custom-Header` can also be retrieved as `x_custom_header`.
  --
  -- @treturn string|nil The value of the header, or `nil` if a header with
  -- `name` was not found in the response. If a header with the same name is present
  -- multiple times in the response, this function will return the value of the
  -- first occurrence of this header.
  -- @usage
  -- -- Given a response with the following headers:
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  --
  -- kong.log.inspect(kong.service.response.get_header("x-custom-header")) -- "bla"
  -- kong.log.inspect(kong.service.response.get_header("X-Another"))       -- "foo bar"
  function response.get_header(name)
    check_phase(header_body_log)

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = response.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function response.get_raw_body()
    -- TODO: implement
  end


  function response.get_body()
    -- TODO: implement
  end


  return response
end


return {
  new = new,
}
