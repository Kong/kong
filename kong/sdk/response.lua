local cjson = require "cjson.safe"
local meta = require "kong.meta"


local ngx = ngx
local fmt = string.format
local type = type
local error = error
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local coroutine = coroutine


local function new(sdk, major_version)
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

  local RESPONSE_PHASES_SET  = {
    header_filter = true,
  }

  local RESPONSE_PHASES_GET  = {
    header_filter = true,
    body_filter   = true,
  }

  local RESPONSE_PHASES_EXIT = {
    rewrite       = true,
    access        = true,
  }

  function _RESPONSE.get_status()
    --local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_GET[phase] then
    --  error(fmt("kong.response.get_status is disabled in the context of %s", phase), 2)
    --end

    return ngx.status
  end


  function _RESPONSE.set_status(code)
    --local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_SET[phase] then
    --  error(fmt("kong.response.set_status is disabled in the context of %s", phase), 2)
    --end

    --if phase ~= "header_filter" and ngx.headers_sent then
    --  error("headers have been sent", 2)
    --end

    if type(code) ~= "number" then
      error("code must be a number", 2)

    elseif code < MIN_STATUS_CODE or code > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if ngx.headers_sent then
      error("headers have been sent", 2)
    end

    ngx.status = code
  end


  function _RESPONSE.get_headers(max_headers)
    --local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_GET[phase] then
    --  error(fmt("kong.response.get_headers is disabled in the context of %s", phase), 2)
    --end

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


  function _RESPONSE.get_header(name)
    --local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_GET[phase] then
    --  error(fmt("kong.response.get_header is disabled in the context of %s", phase), 2)
    --end

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    local header_value = _RESPONSE.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  function _RESPONSE.set_header(name, value)
    local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_SET[phase] then
    --  error(fmt("kong.response.set_header is disabled in the context of %s", phase), 2)
    --end

    if phase ~= "header_filter" and ngx.headers_sent then
      error("headers have been sent", 2)
    end

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    ngx.header[name] = value ~= "" and value or " "
  end


  function _RESPONSE.add_header(name, value)
    local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_SET[phase] then
    --  error(fmt("kong.response.add_header is disabled in the context of %s", phase), 2)
    --end

    if phase ~= "header_filter" and ngx.headers_sent then
      error("headers have been sent", 2)
    end

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    local header = _RESPONSE.get_headers()[name]
    if type(header) ~= "table" then
      header = { header }
    end

    insert(header, value ~= "" and value or " ")

    ngx.header[name] = header
  end


  function _RESPONSE.clear_header(name)
    local phase = ngx.get_phase()
    --if not RESPONSE_PHASES_SET[phase] then
    --  error(fmt("kong.response.clear_header is disabled in the context of %s", phase), 2)
    --end

    if phase ~= "header_filter" and ngx.headers_sent then
      error("headers have been sent", 2)
    end

    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    ngx.header[name] = nil
  end


  function _RESPONSE.set_headers(headers)
    local phase = ngx.get_phase()
    if not RESPONSE_PHASES_SET[phase] then
      error(fmt("kong.response.set_headers is disabled in the context of %s", phase), 2)
    end

    --if phase ~= "header_filter" and ngx.headers_sent then
    --  error("headers have been sent", 2)
    --end

    if type(headers) ~= "table" then
      error("headers must be a table", 2)
    end

    -- Check for type errors first
    for name, value in pairs(headers) do
      local name_t = type(name)
      if name_t ~= "string" then
        error(fmt("invalid name %q: got %s, expected string", name, name_t), 2)
      end

      local value_t = type(value)
      if value_t == "table" then
        for _, array_value in ipairs(value) do
          local array_value_t = type(array_value)
          if array_value_t ~= "string" then
            error(fmt("invalid value in array %q: got %s, expected string", name, array_value_t), 2)
          end
        end

      elseif value_t ~= "string" then
        error(fmt("invalid value in %q: got %s, expected string", name, value_t), 2)
      end
    end

    for name, value in pairs(headers) do
      ngx.header[name] = value ~= "" and value or " "
    end
  end


  --function _RESPONSE.set_raw_body(body)
  --  -- TODO: implement, but how?
  --end
  --
  --
  --function _RESPONSE.set_parsed_body(args, mimetype)
  --  -- TODO: implement, but how?
  --end


  local function send(status, body, headers)
    if ngx.headers_sent then
      error("headers have been sent", 2)
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
        ngx.header[name] = value ~= "" and value or " "
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
    local phase = ngx.get_phase()
    if not RESPONSE_PHASES_EXIT[phase] then
      error(fmt("kong.response.exit is disabled in the context of %s", phase), 2)
    end

    if ngx.headers_sent then
      error("headers have been sent", 2)
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
      for name, value in pairs(headers) do
        local name_t = type(name)
        if name_t ~= "string" then
          error(fmt("invalid header name %q: got %s, expected string", name, name_t), 2)
        end

        local value_t = type(value)
        if value_t == "table" then
          for _, array_value in ipairs(value) do
            local array_value_t = type(array_value)
            if array_value_t ~= "string" then
              error(fmt("invalid header value in array %q: got %s, expected string", name, array_value_t), 2)
            end
          end

        elseif value_t ~= "string" then
          error(fmt("invalid header value in %q: got %s, expected string", name, value_t), 2)
        end
      end
    end

    local ctx = ngx.ctx
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
