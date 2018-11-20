--- Kong helper methods to send HTTP responses to clients.
-- Can be used in the proxy (core/resolver), plugins or Admin API.
-- Most used HTTP status codes and responses are implemented as helper methods.
-- @copyright Copyright 2016-2018 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.responses
-- @usage
--    local responses = require "kong.tools.responses"
--
--    -- In an Admin API endpoint handler, or in one of the plugins' phases.
--    -- the `return` keyword is optional since the execution will be stopped
--    -- anyways. It simply improves code readability.
--    return responses.send_HTTP_OK()
--
--    -- Or:
--    return responses.send_HTTP_NOT_FOUND("No entity for given id")
--
--    -- Raw send() helper:
--    return responses.send(418, "This is a teapot")
local singletons = require "kong.singletons"
local constants = require "kong.constants"
local cjson = require "cjson.safe"
local meta = require "kong.meta"

local type = type

local server_header = meta._SERVER_TOKENS

--- Define the most common HTTP status codes for sugar methods.
-- Each of those status will generate a helper method (sugar)
-- attached to this exported module prefixed with `send_`.
-- Final signature of those methods will be `send_<status_code_key>(message, headers)`. See @{send} for more details on those parameters.
-- @field HTTP_OK 200 OK
-- @field HTTP_CREATED 201 Created
-- @field HTTP_NO_CONTENT 204 No Content
-- @field HTTP_BAD_REQUEST 400 Bad Request
-- @field HTTP_UNAUTHORIZED 401 Unauthorized
-- @field HTTP_FORBIDDEN 403 Forbidden
-- @field HTTP_NOT_FOUND 404 Not Found
-- @field HTTP_METHOD_NOT_ALLOWED 405 Method Not Allowed
-- @field HTTP_CONFLICT 409 Conflict
-- @field HTTP_UNSUPPORTED_MEDIA_TYPE 415 Unsupported Media Type
-- @field HTTP_INTERNAL_SERVER_ERROR Internal Server Error
-- @field HTTP_SERVICE_UNAVAILABLE 503 Service Unavailable
-- @usage return responses.send_HTTP_OK()
-- @usage return responses.HTTP_CREATED("Entity created")
-- @usage return responses.HTTP_INTERNAL_SERVER_ERROR()
-- @table status_codes
local _M = {
  status_codes = {
    HTTP_OK = 200,
    HTTP_CREATED = 201,
    HTTP_NO_CONTENT = 204,
    HTTP_BAD_REQUEST = 400,
    HTTP_UNAUTHORIZED = 401,
    HTTP_FORBIDDEN = 403,
    HTTP_NOT_FOUND = 404,
    HTTP_METHOD_NOT_ALLOWED = 405,
    HTTP_CONFLICT = 409,
    HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    HTTP_INTERNAL_SERVER_ERROR = 500,
    HTTP_BAD_GATEWAY = 502,
    HTTP_SERVICE_UNAVAILABLE = 503,
  }
}

--- Define some default response bodies for some status codes.
-- Some other status codes will have response bodies that cannot be overridden.
-- Example: 204 MUST NOT have content, but if 404 has no content then "Not found" will be set.
-- @field status_codes.HTTP_UNAUTHORIZED Default: Unauthorized
-- @field status_codes.HTTP_NO_CONTENT Always empty.
-- @field status_codes.HTTP_NOT_FOUND Default: Not Found
-- @field status_codes.HTTP_UNAUTHORIZED Default: Unauthorized
-- @field status_codes.HTTP_INTERNAL_SERVER_ERROR Always "Internal Server Error"
-- @field status_codes.HTTP_METHOD_NOT_ALLOWED Always "Method not allowed"
-- @field status_codes.HTTP_BAD_GATEWAY Always: "Bad Gateway"
-- @field status_codes.HTTP_SERVICE_UNAVAILABLE Default: "Service unavailable"
local response_default_content = {
  [_M.status_codes.HTTP_UNAUTHORIZED] = function(content)
    return content or "Unauthorized"
  end,
  [_M.status_codes.HTTP_NO_CONTENT] = function(content)
    return nil
  end,
  [_M.status_codes.HTTP_NOT_FOUND] = function(content)
    return content or "Not found"
  end,
  [_M.status_codes.HTTP_INTERNAL_SERVER_ERROR] = function(content)
    return "An unexpected error occurred"
  end,
  [_M.status_codes.HTTP_METHOD_NOT_ALLOWED] = function(content)
    return "Method not allowed"
  end,
  [_M.status_codes.HTTP_BAD_GATEWAY] = function(content)
    return "Bad Gateway"
  end,
  [_M.status_codes.HTTP_SERVICE_UNAVAILABLE] = function(content)
    return content or "Service unavailable"
  end,
}

-- Return a closure which will be usable to respond with a certain status code.
-- @local
-- @param[type=number] status_code The status for which to define a function
local function send_response(status_code)
  -- Send a JSON response for the closure's status code with the given content.
  -- If the content happens to be an error (500), it will be logged by ngx.log as an ERR.
  -- @see https://github.com/openresty/lua-nginx-module
  -- @param content (Optional) The content to send as a response.
  -- @return ngx.exit (Exit current context)
  return function(content, headers)
    local ctx = ngx.ctx

    if ctx.delay_response and not ctx.delayed_response then
      ctx.delayed_response = {
        status_code = status_code,
        content = content,
        headers = headers,
      }

      coroutine.yield()
    end

    if (status_code == _M.status_codes.HTTP_INTERNAL_SERVER_ERROR
       or status_code == _M.status_codes.HTTP_BAD_GATEWAY)
       and content ~= nil
    then
      ngx.log(ngx.ERR, tostring(content))
    end

    ngx.status = status_code

    if singletons and singletons.configuration then
      if singletons.configuration.enabled_headers[constants.HEADERS.SERVER] then
        ngx.header[constants.HEADERS.SERVER] = server_header

      else
        ngx.header[constants.HEADERS.SERVER] = nil
      end

    else
      ngx.header[constants.HEADERS.SERVER] = server_header
    end

    if headers then
      for k, v in pairs(headers) do
        ngx.header[k] = v
      end
    end

    if type(response_default_content[status_code]) == "function" then
      content = response_default_content[status_code](content)
    end

    local encoded, err
    if content then
      encoded, err = cjson.encode(type(content) == "table" and content or
                                  {message = content})
      if not encoded then
        ngx.log(ngx.ERR, "[admin] could not encode value: ", err)
        ngx.header["Content-Length"] = 0

      else
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.header["Content-Length"] = #encoded + 1
        ngx.say(encoded)
      end

    else
      ngx.header["Content-Length"] = 0
    end

    return ngx.exit(status_code)
  end
end

function _M.flush_delayed_response(ctx)
  ctx.delay_response = false

  if type(ctx.delayed_response_callback) == "function" then
    ctx.delayed_response_callback(ctx)
    return -- avoid tail call
  end

  _M.send(ctx.delayed_response.status_code,
          ctx.delayed_response.content,
          ctx.delayed_response.headers)
end

-- Generate sugar methods (closures) for the most used HTTP status codes.
for status_code_name, status_code in pairs(_M.status_codes) do
  _M["send_" .. status_code_name] = send_response(status_code)
end

local closure_cache = {}

--- Send a response with any status code or body,
-- Not all status codes are available as sugar methods, this function can be
-- used to send any response.
-- For `status_code=5xx` the `content` parameter should be the description of the error that occurred.
-- For `status_code=500` the content will be logged by ngx.log as an ERR.
-- Will call `ngx.say` and `ngx.exit`, terminating the current context.
-- @see ngx.say
-- @see ngx.exit
-- @param[type=number] status_code HTTP status code to send
-- @param body_raw A string or table which will be the body of the sent response. If table, the response will be encoded as a JSON object. If string, the response will be a JSON object and the string will be contained in the `message` property.
-- @param[type=table] headers Response headers to send.
-- @return ngx.exit (Exit current context)
function _M.send(status_code, body, headers)
  local res = closure_cache[status_code]
  if not res then
    res = send_response(status_code)
    closure_cache[status_code] = res
  end

  return res(body, headers)
end

return _M
