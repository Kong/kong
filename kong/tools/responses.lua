-- Kong helper methods to send HTTP responses to clients.
-- Can be used in the proxy, plugins or admin API.
-- Most used status codes and responses are implemented as helper methods.
--
-- @author thibaultcha

-- Define the most used HTTP status codes through Kong
local _M = {
  status_codes = {
    HTTP_OK = 200,
    HTTP_CREATED = 201,
    HTTP_NO_CONTENT = 204,
    HTTP_BAD_REQUEST = 400,
    HTTP_FORBIDDEN = 403,
    HTTP_NOT_FOUND = 404,
    HTTP_METHOD_NOT_ALLOWED = 405,
    HTTP_CONFLICT = 409,
    HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    HTTP_INTERNAL_SERVER_ERROR = 500
  }
}

-- Define some rules that will ALWAYS be applied to some status codes.
-- Ex: 204 must not have content, but if 404 has no content then "Not found" will be set.
local response_default_content = {
  [_M.status_codes.HTTP_NOT_FOUND] = function(content)
    return content and content or "Not found"
  end,
  [_M.status_codes.HTTP_NO_CONTENT] = function(content)
    return nil
  end,
  [_M.status_codes.HTTP_INTERNAL_SERVER_ERROR] = function(content)
    return "An unexpected error occurred"
  end,
  [_M.status_codes.HTTP_METHOD_NOT_ALLOWED] = function(content)
    return "Method not allowed"
  end
}

-- Return a closure which will be usable to respond with a certain status code.
-- @param `status_code` The status for which to define a function
--
-- Send a JSON response for the closure's status code with the given content.
-- If the content happens to be an error (>500), it will be logged by ngx.log as an ERR.
-- @see http://wiki.nginx.org/HttpLuaModule
-- @param `content` (Optional) The content to send as a response.
-- @param `raw`     (Optional) A boolean defining if the `content` should not be serialized to JSON
--                             This useed to send text as JSON in some edge-cases of cjson.
-- @return `ngx.exit()`
local function send_response(status_code)
  local constants = require "kong.constants"
  local cjson = require "cjson"

  return function(content, raw)
    if status_code >= _M.status_codes.HTTP_INTERNAL_SERVER_ERROR then
      if content then
        ngx.log(ngx.ERR, tostring(content))
      end
      ngx.ctx.stop_phases = true -- interrupt other phases of this request
    end

    ngx.status = status_code
    ngx.header["Content-Type"] = "application/json; charset=utf-8"
    ngx.header["Server"] = constants.NAME.."/"..constants.VERSION

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
-- Sends any status code as a response. This is useful for plugins which want to
-- send a response when the status code is not defined in `_M.status_codes` and thus
-- has no sugar method on `_M`.
function _M.send(status_code, content, raw)
  local res = closure_cache[status_code]
  if not res then
    res = send_response(status_code)
    closure_cache[status_code] = res
  end
  return res(content, raw)
end

return _M
