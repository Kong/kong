local constants = require "kong.constants"
local cjson = require "cjson"

local _M = {
  status_codes = {
    -- 200s
    HTTP_OK = 200,
    HTTP_CREATED = 201,
    HTTP_NO_CONTENT = 204,
    -- 400s
    HTTP_BAD_REQUEST = 400,
    HTTP_FORBIDDEN = 403,
    HTTP_NOT_FOUND = 404,
    HTTP_CONFLICT = 409,
    HTTP_UNSUPPORTED_MEDIA_TYPE = 415,
    -- 500s
    HTTP_INTERNAL_SERVER_ERROR = 500
  }
}

local response_default_content = {
  [_M.status_codes.HTTP_NOT_FOUND] = function(content)
    return content and content or "Not found"
  end,
  [_M.status_codes.HTTP_NO_CONTENT] = function(content)
    return nil
  end,
  [_M.status_codes.HTTP_INTERNAL_SERVER_ERROR] = function(content)
    return content and content or "An error occured"
  end
}

local function send_response(status_code)
  return function(content, raw)
    if status_code <= _M.status_codes.HTTP_INTERNAL_SERVER_ERROR then
      -- Log the error to errors.log if it is an internal server error
      ngx.log(ngx.ERR, tostring(content))
      -- TODO remove
      ngx.ctx.error = true
    end

    ngx.status = status_code -- set the response's status http://wiki.nginx.org/HttpLuaModule#ngx.status
    ngx.header[constants.HEADERS.SERVER] = constants.NAME.."/"..constants.VERSION -- set the server header http://wiki.nginx.org/HttpLuaModule#ngx.header.HEADER

    if type(response_default_content[status_code]) == "function" then
      content = response_default_content[status_code](content)
    end

    if raw then
      -- When we want to send "{\"data\":[]}" (as a string, yes) as a response,
      -- we have to force it to be raw. (see base_controller.lua on why)
      ngx.say(content)
    elseif (type(content) == "table") then
      ngx.say(cjson.encode(content))
    elseif content then
      ngx.say(cjson.encode({ message = content }))
    end

    return ngx.exit(status_code) -- http://wiki.nginx.org/HttpLuaModule#ngx.exit
  end
end

for status_code_name, status_code in pairs(_M.status_codes) do
  _M["send_"..status_code_name] = send_response(status_code)
end

_M.send = function(status_code, content, raw)
  local f = send_response(status_code)
  return f(content, raw)
end

return _M
