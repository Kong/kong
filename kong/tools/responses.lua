--- Kong helper methods to send HTTP responses to clients.
-- Can be used in the proxy (core/resolver), plugins or Admin API.
-- Most used HTTP status codes and responses are implemented as helper methods.
--
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
local cjson = require "cjson"
local meta = require "kong.meta"

--local server_header = _KONG._NAME.."/".._KONG._VERSION
local server_header = meta._NAME.."/"..meta._VERSION

--- Define the most common HTTP status codes for sugar methods.
-- Each of those status will generate a helper method (sugar)
-- attached to this exported module prefixed with `send_`.
-- Final signature of those methods will be `send_<status_code_key>(message, raw, headers)`. See @{send} for more details on those parameters.
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
    HTTP_INTERNAL_SERVER_ERROR = 500
  }
}

--- Define some default response bodies for some status codes.
-- Some other status codes will have response bodies that cannot be overriden.
-- Example: 204 MUST NOT have content, but if 404 has no content then "Not found" will be set.
-- @field status_codes.HTTP_UNAUTHORIZED Default: Unauthorized
-- @field status_codes.HTTP_NO_CONTENT Always empty.
-- @field status_codes.HTTP_NOT_FOUND Default: Not Found
-- @field status_codes.HTTP_UNAUTHORIZED Default: Unauthorized
-- @field status_codes.HTTP_INTERNAL_SERVER_ERROR Always "Internal Server Error"
-- @field status_codes.HTTP_METHOD_NOT_ALLOWED Always "Method not allowed"
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
  end
}

-- Return a closure which will be usable to respond with a certain status code.
-- @local
-- @param[type=number] status_code The status for which to define a function
local function send_response(status_code)
  -- Send a JSON response for the closure's status code with the given content.
  -- If the content happens to be an error (>500), it will be logged by ngx.log as an ERR.
  -- @see https://github.com/openresty/lua-nginx-module
  -- @param content (Optional) The content to send as a response.
  -- @param raw     (Optional) A boolean defining if the `content` should not be serialized to JSON
  --                             This useed to send text as JSON in some edge-cases of cjson.
  -- @return ngx.exit (Exit current context)
  return function(content, raw, headers)
    if status_code >= _M.status_codes.HTTP_INTERNAL_SERVER_ERROR then
      if content then
        ngx.log(ngx.ERR, tostring(content))
      end
    end

    ngx.status = status_code
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.header["Server"] = server_header

    if headers then
      for k, v in pairs(headers) do
        ngx.header[k] = v
      end
    end

    if type(response_default_content[status_code]) == "function" then
      content = response_default_content[status_code](content)
    end

    if raw then
      -- When we want to send an empty array, such as "{\"data\":[]}"
      -- cjson has a flaw and encodes a Lua `{}` as a JSON `{}`.
      -- This allows to send plain string JSON as "[]".
      ngx.say(content)
    elseif (type(content) == "table") then
      ngx.say(cjson.encode(content))
    elseif content then
      ngx.say(cjson.encode({ message = content }))
    end

    return ngx.exit(status_code)
  end
end

-- Generate sugar methods (closures) for the most used HTTP status codes.
for status_code_name, status_code in pairs(_M.status_codes) do
  _M["send_"..status_code_name] = send_response(status_code)
end

local closure_cache = {}

--- Send a response with any status code or body,
-- Not all status codes are available as sugar methods, this function can be
-- used to send any response.
-- If the `status_code` parameter is in the 5xx range, it is expectde that the `content` parameter be the error encountered. It will be logged and the response body will be empty. The user will just receive a 500 status code.
-- Will call `ngx.say` and `ngx.exit`, terminating the current context.
-- @see ngx.say
-- @see ngx.exit
-- @param[type=number] status_code HTTP status code to send
-- @param body A string or table which will be the body of the sent response. If table, the response will be encoded as a JSON object. If string, the response will be a JSON object and the string will be contained in the `message` property. Except if the `raw` parameter is set to `true`.
-- @param[type=boolean] raw If true, send the `body` as it is.
-- @param[type=table] headers Response headers to send.
-- @return ngx.exit (Exit current context)
function _M.send(status_code, body, raw, headers)
  local res = closure_cache[status_code]
  if not res then
    res = send_response(status_code)
    closure_cache[status_code] = res
  end
  return res(body, raw, headers)
end

return _M
