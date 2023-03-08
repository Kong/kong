local http_constants = require "kong.tools.http_constants"
local cjson = require "cjson.safe"

local fmt = string.format
local error = error
local type = type
local ipairs = ipairs
local setmetatable = setmetatable
local cjson_encode = cjson.encode
local ngx = ngx

local CONTENT_TYPE_NAME = http_constants.headers.CONTENT_TYPE
local CONTENT_LENGTH_NAME = http_constants.headers.CONTENT_LENGTH
local CONTENT_TYPE_JSON = "application/json; charset=utf-8"

local _M = {
  name = "json",
  priority = 100,
  supported_media_types = {
    { type = "application", sub_type = "json" },
  },
}

local mt = { __index = _M }


local function convert(body)
  if type(body) == "table" then
    local json, err = cjson_encode(body)
    if err then
      error(fmt("body encoding failed while flushing response: %s", err), 2)
    end
    body = json
  end

  return body
end


function _M:match(other_type, other_subtype)
  for _, mime_type in ipairs(self.supported_media_types) do
    if mime_type.type == other_type or mime_type.type == "*" then
      if mime_type.sub_type == other_subtype or mime_type.sub_type == "*" then
        return true
      end
    end
  end

  return false
end


function _M:handle(body, status, options)
  body = convert(body)

  if not options.explicit_content_type then
    ngx.header[CONTENT_TYPE_NAME] = CONTENT_TYPE_JSON
  end

  if not options.explicit_content_length then
    local length = body ~= nil and #body or 0
    ngx.header[CONTENT_LENGTH_NAME] = length
  end

  if body ~= nil then
    if options.is_header_filter_phase then
      ngx.ctx.response_body = body
    else
      ngx.print(body)
    end
  end
end


local function new(kong)
  local self = {}
  return setmetatable(self, mt)
end


return {
  new = new
}
