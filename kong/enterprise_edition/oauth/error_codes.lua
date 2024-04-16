-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local fmt = string.format
local concat = table.concat
local insert = table.insert

--[[
Error codes as defined in he OAuth 2.0 Authorization Framework: Bearer Token Usage
https://www.rfc-editor.org/rfc/rfc6750#section-3.1

When a request fails, the resource server responds using the
appropriate HTTP status code (typically, 400, 401, 403, or 405) and
includes one of the following error codes in the response:

invalid_request
      The request is missing a required parameter, includes an
      unsupported parameter or parameter value, repeats the same
      parameter, uses more than one method for including an access
      token, or is otherwise malformed.  The resource server SHOULD
      respond with the HTTP 400 (Bad Request) status code.

invalid_token
      The access token provided is expired, revoked, malformed, or
      invalid for other reasons.  The resource SHOULD respond with
      the HTTP 401 (Unauthorized) status code.  The client MAY
      request a new access token and retry the protected resource
      request.

insufficient_scope
      The request requires higher privileges than provided by the
      access token.  The resource server SHOULD respond with the HTTP
      403 (Forbidden) status code and MAY include the "scope"
      attribute with the scope necessary to access the protected
      resource.

If the request lacks any authentication information (e.g., the client
was unaware that authentication is necessary or attempted using an
unsupported authentication method), the resource server SHOULD NOT
include an error code or other error information.
--]]
local INVALID_TOKEN = "invalid_token"
local INVALID_REQUEST = "invalid_request"
local INSUFFICIENT_SCOPE = "insufficient_scope"

local HTTP_BAD_REQUEST = 400
local HTTP_UNAUTHORIZED = 401
local HTTP_FORBIDDEN = 403



-- Define the base Error class
local Error = {}

--- Creates a new instance of the `Error` class.
--
---@tparam table e A table with the following optional fields:
--   - `status_code`: an HTTP status code (e.g. 400, 401, etc.).
--   - `error_code`: a string representing an error code that will be included in the `WWW-Authenticate` header.
--   - `error_description`: a string describing the error that will be included in the `WWW-Authenticate` header.
--   - `message`: a message that will be exposed after the HTTP status code.
--   - `log_msg`: a message that will be logged.
--   - `expose_error_code`: a boolean flag to enable or disable the exposure of the `error_code` and corresponding `error_description`.
--
---@return (table) A new instance of the `GenericError` class.
function Error:new(e)
  e = e or {}
  e.status_code = e.status_code or 500
  e.error_code = e.error_code or nil
  e.error_description = e.error_description or nil
  e.message = e.message or "internal server error"
  e.log = e.log_msg or e.message
  e.expose_error_code = e.expose_error_code or false
  e.realm = e.realm or "kong"
  e.fields = e.fields or { realm = e.realm }
  e.fields.realm = e.fields.realm or e.realm
  e.token_type = e.token_type or "Bearer"
  setmetatable(e, self)
  return e
end

--- Check if the `error_code` and corresponding `error_description` should be exposed.
---
--- The method will return true if `expose_error_code` is set to true and `error_code`
--- is present, false otherwise.
--
--- @return boolean - indicating whether to expose error_code
function Error:expose_error()
  if self.expose_error_code and self.error_code then
    return true
  end
  return false
end

--- Builds the `WWW-Authenticate` header for the error response.
--- RFC https://www.rfc-editor.org/rfc/rfc6750#section-3
--
---@return (table) - the headers for use in the error response.
function Error:build_www_auth_header()
  local fields = {}
  local i = 0
  if self.fields then
    for k, v in pairs(self.fields) do
      i = i + 1
      fields[i] = fmt('%s="%s"', k, v)
    end
  end

  -- we want a constant ordering of the fields
  -- and error_code and error_description should be last
  if i > 1 then
    table.sort(fields)
  end

  -- add header fields for error_code and error_description if set and required
  if self:expose_error() then
    i = i + 1
    fields[i] = fmt('error="%s"', self.error_code)

    if self.error_description then
      i = i + 1
      fields[i] = fmt('error_description="%s"', self.error_description)
    end
  end

  local www_header = self.token_type

  if i > 0 then
    www_header = www_header .. " " .. concat(fields, ", ")
  end

  return www_header
end

--- A class representing a Forbidden HTTP error.
-- Inherits from the `Error` class.
-- @field status_code The HTTP status code for the error (403).
-- @field error_code The error code for the error (INSUFFICIENT_SCOPE).
-- @field message The error message for the error ("Forbidden").
-- @table ForbiddenError
local ForbiddenError = {}
setmetatable(ForbiddenError, { __index = Error })

--- Creates a new `ForbiddenError` object.
-- @tparam table e An optional table with error properties to override the default values.
-- @treturn ForbiddenError The new `ForbiddenError` object.
function ForbiddenError:new(e)
  e.status_code = HTTP_FORBIDDEN
  e.error_code = e.error_code or INSUFFICIENT_SCOPE
  e.message = e.message or "Forbidden"
  local obj = Error:new(e)
  setmetatable(obj, self)
  self.__index = self
  return obj
end

local UnauthorizedError = {}
--- A class representing an Unauthorized HTTP error.
-- Inherits from the `Error` class.
-- @field status_code The HTTP status code for the error (401).
-- @field error_code The error code for the error (INVALID_TOKEN).
-- @field message The error message for the error ("Unauthorized").
-- @table UnauthorizedError
setmetatable(UnauthorizedError, { __index = Error })

--- Creates a new `UnauthorizedError` object.
-- @tparam table e An optional table with error properties to override the default values.
-- @treturn UnauthorizedError The new `UnauthorizedError` object.
function UnauthorizedError:new(e)
  e.status_code = HTTP_UNAUTHORIZED
  e.error_code = e.error_code or INVALID_TOKEN
  e.message = e.message or "Unauthorized"
  local obj = Error:new(e)
  setmetatable(obj, self)
  self.__index = self
  return obj
end

local BadRequestError = {}
--- A class representing a Bad Request HTTP error.
-- Inherits from the `Error` class.
-- @field status_code The HTTP status code for the error (400).
-- @field error_code The error code for the error (INVALID_REQUEST).
-- @field message The error message for the error ("Bad Request").
-- @table BadRequestError
setmetatable(BadRequestError, { __index = Error })

--- Creates a new `BadRequestError` object.
-- @tparam table e An optional table with error properties to override the default values.
-- @treturn BadRequestError The new `BadRequestError` object.
function BadRequestError:new(e)
  e.status_code = HTTP_BAD_REQUEST
  e.error_code = e.error_code or INVALID_REQUEST
  e.message = e.mesasge or "Bad Request"
  local obj = Error:new(e)
  setmetatable(obj, self)
  self.__index = self
  return obj
end

return {
  UnauthorizedError = UnauthorizedError,
  ForbiddenError = ForbiddenError,
  BadRequestError = BadRequestError,
  INSUFFICIENT_SCOPE = INSUFFICIENT_SCOPE,
  INVALID_REQUEST = INVALID_REQUEST,
  INVALID_TOKEN = INVALID_TOKEN,
}
