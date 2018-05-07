local cjson = require "cjson.safe"
local meta = require "kong.meta"


local ngx = ngx
local type = type
local find = string.find
local lower = string.lower
local error = error
local pairs = pairs
local ipairs = ipairs
local insert = table.insert
local coroutine = coroutine


local function new(sdk, major_version)
  local _RESPONSE = {}

  local SERVER_HEADER_NAME  = "Server"
  local SERVER_HEADER_VALUE = meta._NAME .. "/" .. meta._VERSION

  local MIN_HEADERS         = 1
  local MAX_HEADERS_DEFAULT = 100
  local MAX_HEADERS         = 1000

  local DEFAULT_BODY = {
    [ngx.HTTP_NOT_ALLOWED]           = "Method Not Allowed",
    [ngx.HTTP_UNAUTHORIZED]          = "Unauthorized",
    [ngx.HTTP_SERVICE_UNAVAILABLE]   = "Service Unavailable",
    [ngx.HTTP_INTERNAL_SERVER_ERROR] = "Internal Server Error",
  }


  function _RESPONSE.get_status()
    return ngx.status
  end


  function _RESPONSE.set_status(code)
    if type(code) ~= "number" then
      error("code must be a number", 2)

    elseif code < 100 or code > 599 then
      error("code must be a number between 100 and 599", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.status = code
  end


  function _RESPONSE.get_headers(max_headers)
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
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.header[name] = value
  end


  function _RESPONSE.add_header(name, value)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    local header = _RESPONSE.get_headers()[name]
    if type(header) ~= "table" then
      header = { header }
    end

    insert(header, value ~= "" and value or " ")

    ngx.header[name] = header
  end


  function _RESPONSE.clear_header(name)
    if type(name) ~= "string" then
      error("name must be a string", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    ngx.header[name] = nil
  end


  function _RESPONSE.set_headers(headers)
    if type(headers) ~= "table" then
      error("headers must be a table", 2)
    end

    -- Check for type errors first
    for name, value in pairs(headers) do
      local name_t = type(name)
      if name_t ~= "string" then
        error(("invalid name %q: got %s, expected string"):format(name, name_t), 2)
      end

      local value_t = type(value)
      if value_t == "table" then
        for _, array_value in ipairs(value) do
          local array_value_t = type(array_value)
          if array_value_t ~= "string" then
            error(("invalid value in array %q: got %s, expected string"):format(name, array_value_t), 2)
          end
        end

      elseif value_t ~= "string" then
        error(("invalid value in %q: got %s, expected string"):format(name, value_t), 2)
      end
    end

    for name, value in pairs(headers) do
      ngx.header[name] = value ~= "" and value or " "
    end
  end


  function _RESPONSE.get_raw_body()
    -- TODO: implement
  end


  function _RESPONSE.get_parsed_body()
    -- TODO: implement
  end


  function _RESPONSE.set_raw_body(body)
    -- TODO: implement
  end


  function _RESPONSE.set_parsed_body(args, mimetype)
    -- TODO: implement
  end


  local function send(code, body, headers)
    ngx.status = code
    ngx.header[SERVER_HEADER_NAME] = SERVER_HEADER_VALUE
    if headers then
      for k, v in pairs(headers) do
        ngx.header[k] = v
      end
    end

    if code == ngx.HTTP_NO_CONTENT then
      body = DEFAULT_BODY[ngx.HTTP_NO_CONTENT]

    elseif code == ngx.HTTP_NOT_ALLOWED then
      body = DEFAULT_BODY[ngx.HTTP_NOT_ALLOWED]

    elseif code == ngx.HTTP_INTERNAL_SERVER_ERROR then
      if body then
        ngx.log(ngx.ERR, body)
      end

      body = DEFAULT_BODY[ngx.HTTP_INTERNAL_SERVER_ERROR]

    elseif not body then
      body = DEFAULT_BODY[code]
    end

    if body then
      local content_type = ngx.header["Content-Type"]
      if content_type == nil or find(lower(content_type), "application/json", 1, true) then
        local json = cjson.encode(type(body) == "table" and body or { message = body })
        if json then
          if not content_type then
            ngx.header["Content-Type"] = "application/json; charset=utf-8"
          end

          ngx.say(json)

        else
          ngx.print(body)
        end

      else
        ngx.print(body)
      end
    end

    return ngx.exit(code)
  end


  local function flush(ctx)
    return send(ctx.status_code, ctx.content, ctx.headers)
  end


  function _RESPONSE.exit(code, body, headers)
    if code ~= nil then
      if type(code) ~= "number" then
        error("code must be a number", 2)

      elseif code < 100 or code > 599 then
        error("code must be a number between 100 and 599", 2)
      end
    end

    if body ~= nil and type(body) ~= "string" and type(body) ~= "table" then
      error("body must be a nil, string or table", 2)
    end

    if headers ~= nil and type(body) ~= "table" then
      error("headers must be a nil or table", 2)
    end

    if ngx.headers_sent then
      return nil, "headers have been sent"
    end

    local ctx = ngx.ctx
    if ctx.delay_response and not ctx.delayed_response then
      ctx.delayed_response = {
        status_code = code,
        content     = body,
        headers     = headers,
      }

      ctx.delayed_response_callback = flush
      coroutine.yield()
    end

    send(code, body, headers)
  end

  return _RESPONSE
end


return {
  new = new,
}
