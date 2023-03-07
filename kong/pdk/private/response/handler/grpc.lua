local http_constants = require "kong.tools.http_constants"

local type = type
local error = error
local ngx = ngx
local setmetatable = setmetatable

local GRPC_STATUS_NAME = "grpc-status"
local GRPC_MESSAGE_NAME = "grpc-message"
local GRPC_STATUS_UNKNOWN = 2
local HTTP_TO_GRPC_STATUS = {
  [200] = 0,
  [400] = 3,
  [401] = 16,
  [403] = 7,
  [404] = 5,
  [409] = 6,
  [429] = 8,
  [499] = 1,
  [500] = 13,
  [501] = 12,
  [503] = 14,
  [504] = 4,
}
local GRPC_MESSAGES = {
  [0] = "OK",
  [1] = "Canceled",
  [2] = "Unknown",
  [3] = "InvalidArgument",
  [4] = "DeadlineExceeded",
  [5] = "NotFound",
  [6] = "AlreadyExists",
  [7] = "PermissionDenied",
  [8] = "ResourceExhausted",
  [9] = "FailedPrecondition",
  [10] = "Aborted",
  [11] = "OutOfRange",
  [12] = "Unimplemented",
  [13] = "Internal",
  [14] = "Unavailable",
  [15] = "DataLoss",
  [16] = "Unauthenticated",
}

local CONTENT_LENGTH_NAME = http_constants.headers.CONTENT_LENGTH


local _M = {
  name = "grpc",
  priority = 90,
}

local mt = { __index = _M }


function _M:match(other_type, other_subtype)
  return (other_type == "application" and other_subtype == "grpc")
    or ngx.ctx.is_grpc_request
end


function _M:handle(body, status, options)
  local is_grpc_output = options.parsed_mime_type.type == "application"
    and options.parsed_mime_type.subtype == "grpc"

  local grpc_status = ngx.header[GRPC_STATUS_NAME]
  if not grpc_status then
    grpc_status = HTTP_TO_GRPC_STATUS[status]
    if not grpc_status then
      if status >= 500 and status <= 599 then
        grpc_status = HTTP_TO_GRPC_STATUS[500]
      elseif status >= 400 and status <= 499 then
        grpc_status = HTTP_TO_GRPC_STATUS[400]
      elseif status >= 200 and status <= 299 then
        grpc_status = HTTP_TO_GRPC_STATUS[200]
      else
        grpc_status = GRPC_STATUS_UNKNOWN
      end
    end
    ngx.header[GRPC_STATUS_NAME] = grpc_status
  end

  if type(body) == "table" then
    if is_grpc_output then
      error("table body encoding with gRPC is not supported", 2)

    elseif type(body.message) == "string" then
      body = body.message

    else
      self.log.warn("body was removed because table body encoding with " ..
        "gRPC is not supported")
      body = nil
    end
  end

  local ctx = ngx.ctx

  if body == nil then
    if not ngx.header[CONTENT_LENGTH_NAME] then
      ngx.header[CONTENT_LENGTH_NAME] = 0
    end

    if grpc_status and not ngx.header[GRPC_MESSAGE_NAME] then
      ngx.header[GRPC_MESSAGE_NAME] = GRPC_MESSAGES[grpc_status]
    end

    if options.is_header_filter_phase then
      ctx.response_body = ""
    else
      ngx.print() -- avoid default content
    end

    return
  end

  if is_grpc_output then
    if not ngx.header[CONTENT_LENGTH_NAME] then
      ngx.header[CONTENT_LENGTH_NAME] = #body
    end

    if grpc_status and not ngx.header[GRPC_MESSAGE_NAME] then
      ngx.header[GRPC_MESSAGE_NAME] = GRPC_MESSAGES[grpc_status]
    end

    if options.is_header_filter_phase then
      ctx.response_body = body
    else
      ngx.print(body)
    end

  else
    ngx.header[CONTENT_LENGTH_NAME] = 0
    ngx.header[GRPC_MESSAGE_NAME] = body

    if options.is_header_filter_phase then
      ctx.response_body = ""
    else
      ngx.print() -- avoid default content
    end

  end

end


local function new(kong)
  local self = {
    log = kong and kong.log,
  }
  return setmetatable(self, mt)
end


return {
  new = new
}
