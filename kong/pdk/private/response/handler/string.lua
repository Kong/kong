local http_constants = require "kong.tools.http_constants"
local setmetatable = setmetatable
local ngx = ngx

local CONTENT_LENGTH_NAME  = http_constants.headers.CONTENT_LENGTH

local _M = {
  name = "string",
  priority = 0,
}

local mt = { __index = _M }


function _M:match(other_type, other_subtype)
  return  true
end


function _M:handle(body, status, options)
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
