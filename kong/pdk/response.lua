local cjson = require "cjson.safe"
local meta = require "kong.meta"
local checks = require "kong.pdk.private.checks"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local fmt = string.format
local type = type
local error = error
local pairs = pairs
local insert = table.insert
local coroutine = coroutine
local normalize_header = checks.normalize_header
local normalize_multi_header = checks.normalize_multi_header
local validate_header = checks.validate_header
local validate_headers = checks.validate_headers
local check_phase = phase_checker.check


local PHASES = phase_checker.phases


local header_body_log = phase_checker.new(PHASES.header_filter,
                                          PHASES.body_filter,
                                          PHASES.log)

local rewrite_access = phase_checker.new(PHASES.rewrite,
                                         PHASES.access)

local rewrite_access_header = phase_checker.new(PHASES.rewrite,
                                                PHASES.access,
                                                PHASES.header_filter)


local function new(pdk, major_version)
  local _RESPONSE = {}

  local MIN_HEADERS          = 1
  local MAX_HEADERS_DEFAULT  = 100
  local MAX_HEADERS          = 1000

  local MIN_STATUS_CODE      = 100
  local MAX_STATUS_CODE      = 599

  local SERVER_HEADER_NAME   = "Server"
  local SERVER_HEADER_VALUE  = meta._NAME .. "/" .. meta._VERSION

  local CONTENT_LENGTH_NAME  = "Content-Length"
  local CONTENT_TYPE_NAME    = "Content-Type"
  local CONTENT_TYPE_JSON    = "application/json; charset=utf-8"


  function _RESPONSE.get_status()
    check_phase(header_body_log)

    return ngx.status
  end


  function _RESPONSE.get_header(name)
    check_phase(header_body_log)

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    local header_value = _RESPONSE.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _RESPONSE.get_headers(max_headers)
    check_phase(header_body_log)

    if max_headers == nil then
      return ngx.resp.get_headers(MAX_HEADERS_DEFAULT)
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return ngx.resp.get_headers(max_headers)
  end


  function _RESPONSE.get_source()
    check_phase(header_body_log)

    if ngx.ctx.KONG_PROXIED then
      return "service"
    end

    if ngx.ctx.KONG_EXITED then
      return "exit"
    end

    return "error"
  end


  function _RESPONSE.set_status(status)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    ngx.status = status
  end


  function _RESPONSE.set_header(name, value)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_header(name, value)

    ngx.header[name] = normalize_header(value)
  end


  function _RESPONSE.add_header(name, value)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_header(name, value)

    local new_value = _RESPONSE.get_headers()[name]
    if type(new_value) ~= "table" then
      new_value = { new_value }
    end

    insert(new_value, normalize_header(value))

    ngx.header[name] = new_value
  end


  function _RESPONSE.clear_header(name)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    ngx.header[name] = nil
  end


  function _RESPONSE.set_headers(headers)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_headers(headers)

    for name, value in pairs(headers) do
      ngx.header[name] = normalize_multi_header(value)
    end
  end


  --function _RESPONSE.set_raw_body(body)
  --  -- TODO: implement, but how?
  --end
  --
  --
  --function _RESPONSE.set_body(args, mimetype)
  --  -- TODO: implement, but how?
  --end


  local function send(status, body, headers)
    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    local json
    if type(body) == "table" then
      local err
      json, err = cjson.encode(body)
      if err then
        return nil, err
      end
    end

    ngx.status = status
    ngx.header[SERVER_HEADER_NAME] = SERVER_HEADER_VALUE

    if headers ~= nil then
      for name, value in pairs(headers) do
        ngx.header[name] = normalize_multi_header(value)
      end
    end

    if json ~= nil then
      ngx.header[CONTENT_TYPE_NAME]   = CONTENT_TYPE_JSON
      ngx.header[CONTENT_LENGTH_NAME] = #json
      ngx.print(json)

    elseif body ~= nil then
      ngx.header[CONTENT_LENGTH_NAME] = #body
      ngx.print(body)

    else
      ngx.header[CONTENT_LENGTH_NAME] = 0
    end

    return ngx.exit(status)
  end


  local function flush(ctx)
    ctx = ctx or ngx.ctx
    local response = ctx.delayed_response
    return send(response.status_code, response.content, response.headers)
  end


  function _RESPONSE.exit(status, body, headers)
    check_phase(rewrite_access)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if body ~= nil and type(body) ~= "string" and type(body) ~= "table" then
      error("body must be a nil, string or table", 2)
    end

    if headers ~= nil and type(headers) ~= "table" then
      error("headers must be a nil or table", 2)
    end

    if headers ~= nil then
      validate_headers(headers)
    end

    local ctx = ngx.ctx
    ctx.KONG_EXITED = true
    if ctx.delay_response and not ctx.delayed_response then
      ctx.delayed_response = {
        status_code = status,
        content     = body,
        headers     = headers,
      }

      ctx.delayed_response_callback = flush
      coroutine.yield()

    else
      return send(status, body, headers)
    end
  end

  return _RESPONSE
end


return {
  new = new,
}
