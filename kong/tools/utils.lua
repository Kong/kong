-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

---
-- Module containing some general utility functions used in many places in Kong.
--
-- NOTE: Before implementing a function here, consider if it will be used in many places
-- across Kong. If not, a local function in the appropriate module is preferred.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module kong.tools.utils

local pl_stringx = require "pl.stringx"
local pl_path = require "pl.path"
local pl_file = require "pl.file"

local type          = type
local pairs         = pairs
local ipairs        = ipairs
local tostring      = tostring
local tonumber      = tonumber
local sort          = table.sort
local concat        = table.concat
local fmt           = string.format
local find          = string.find
local join          = pl_stringx.join
local split         = pl_stringx.split
local re_match      = ngx.re.match
local match         = string.match
local setmetatable  = setmetatable


local _M = {}


do
  local url = require "socket.url"

  --- URL escape and format key and value
  -- values should be already decoded or the `raw` option should be passed to prevent double-encoding
  local function encode_args_value(key, value, raw)
    if not raw then
      key = url.escape(key)
    end
    if value ~= nil then
      if not raw then
        value = url.escape(value)
      end
      return fmt("%s=%s", key, value)
    else
      return key
    end
  end

  local function compare_keys(a, b)
    local ta = type(a)
    if ta == type(b) then
      return a < b
    end
    return ta == "number" -- numbers go first, then the rest of keys (usually strings)
  end


  -- Recursively URL escape and format key and value
  -- Handles nested arrays and tables
  local function recursive_encode_args(parent_key, value, raw, no_array_indexes, query)
    local sub_keys = {}
    for sk in pairs(value) do
      sub_keys[#sub_keys + 1] = sk
    end
    sort(sub_keys, compare_keys)

    local sub_value, next_sub_key
    for _, sub_key in ipairs(sub_keys) do
      sub_value = value[sub_key]

      if type(sub_key) == "number" then
        if no_array_indexes then
          next_sub_key = parent_key .. "[]"
        else
          next_sub_key = ("%s[%s]"):format(parent_key, tostring(sub_key))
        end
      else
        next_sub_key = ("%s.%s"):format(parent_key, tostring(sub_key))
      end

      if type(sub_value) == "table" then
        recursive_encode_args(next_sub_key, sub_value, raw, no_array_indexes, query)
      else
        query[#query+1] = encode_args_value(next_sub_key, sub_value, raw)
      end
    end
  end


  local ngx_null = ngx.null

  --- Encode a Lua table to a querystring
  -- Tries to mimic ngx_lua's `ngx.encode_args`, but has differences:
  -- * It percent-encodes querystring values.
  -- * It also supports encoding for bodies (only because it is used in http_client for specs.
  -- * It encodes arrays like Lapis instead of like ngx.encode_args to allow interacting with Lapis
  -- * It encodes ngx.null as empty strings
  -- * It encodes true and false as "true" and "false"
  -- * It is capable of encoding nested data structures:
  --   * An array access is encoded as `arr[1]`
  --   * A struct access is encoded as `struct.field`
  --   * Nested structures can use both: `arr[1].field[3]`
  -- @see https://github.com/Mashape/kong/issues/749
  -- @param[type=table] args A key/value table containing the query args to encode.
  -- @param[type=boolean] raw If true, will not percent-encode any key/value and will ignore special boolean rules.
  -- @param[type=boolean] no_array_indexes If true, arrays/map elements will be
  --                      encoded without an index: 'my_array[]='. By default,
  --                      array elements will have an index: 'my_array[0]='.
  -- @treturn string A valid querystring (without the prefixing '?')
  function _M.encode_args(args, raw, no_array_indexes)
    local query = {}
    local keys = {}

    for k in pairs(args) do
      keys[#keys+1] = k
    end

    sort(keys, compare_keys)

    for _, key in ipairs(keys) do
      local value = args[key]
      if type(value) == "table" then
        recursive_encode_args(key, value, raw, no_array_indexes, query)
      elseif value == ngx_null then
        query[#query+1] = encode_args_value(key, "")
      elseif  value ~= nil or raw then
        value = tostring(value)
        if value ~= "" then
          query[#query+1] = encode_args_value(key, value, raw)
        elseif raw or value == "" then
          query[#query+1] = key
        end
      end
    end

    return concat(query, "&")
  end

  local function decode_array(t)
    local keys = {}
    local len  = 0
    for k in pairs(t) do
      len = len + 1
      local number = tonumber(k)
      if not number then
        return nil
      end
      keys[len] = number
    end

    sort(keys)
    local new_t = {}

    for i=1,len do
      if keys[i] ~= i then
        return nil
      end
      new_t[i] = t[tostring(i)]
    end

    return new_t
  end

  -- Parses params in post requests
  -- Transforms "string-like numbers" inside "array-like" tables into numbers
  -- (needs a complete array with no holes starting on "1")
  --   { x = {["1"] = "a", ["2"] = "b" } } becomes { x = {"a", "b"} }
  -- Transforms empty strings into ngx.null:
  --   { x = "" } becomes { x = ngx.null }
  -- Transforms the strings "true" and "false" into booleans
  --   { x = "true" } becomes { x = true }
  function _M.decode_args(args)
    local new_args = {}

    for k, v in pairs(args) do
      if type(v) == "table" then
        v = decode_array(v) or v
      elseif v == "" then
        v = ngx_null
      elseif v == "true" then
        v = true
      elseif v == "false" then
        v = false
      end
      new_args[k] = v
    end

    return new_args
  end

end


--- Checks whether a request is https or was originally https (but already
-- terminated). It will check in the current request (global `ngx` table). If
-- the header `X-Forwarded-Proto` exists -- with value `https` then it will also
-- be considered as an https connection.
-- @param trusted_ip boolean indicating if the client is a trusted IP
-- @param allow_terminated if truthy, the `X-Forwarded-Proto` header will be checked as well.
-- @return boolean or nil+error in case the header exists multiple times
_M.check_https = function(trusted_ip, allow_terminated)
  if ngx.var.scheme:lower() == "https" then
    return true
  end

  if not allow_terminated then
    return false
  end

  -- if we trust this IP, examine it's X-Forwarded-Proto header
  -- otherwise, we fall back to relying on the client scheme
  -- (which was either validated earlier, or we fall through this block)
  if trusted_ip then
    local scheme = ngx.req.get_headers()["x-forwarded-proto"]

    -- we could use the first entry (lower security), or check the contents of
    -- each of them (slow). So for now defensive, and error
    -- out on multiple entries for the x-forwarded-proto header.
    if type(scheme) == "table" then
      return nil, "Only one X-Forwarded-Proto header allowed"
    end

    return tostring(scheme):lower() == "https"
  end

  return false
end

--- Try to load a module.
-- Will not throw an error if the module was not found, but will throw an error if the
-- loading failed for another reason (eg: syntax error).
-- @param module_name Path of the module to load (ex: kong.plugins.keyauth.api).
-- @return success A boolean indicating whether the module was found.
-- @return module The retrieved module, or the error in case of a failure
function _M.load_module_if_exists(module_name)
  local status, res = xpcall(function()
    return require(module_name)
  end, debug.traceback)
  if status then
    return true, res
  -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
  elseif type(res) == "string" and find(res, "module '" .. module_name .. "' not found", nil, true) then
    return false, res
  else
    error("error loading module '" .. module_name .. "':\n" .. res)
  end
end


--- Validates a header name.
-- Checks characters used in a header name to be valid, as per nginx only
-- a-z, A-Z, 0-9 and '-' are allowed.
-- @param name (string) the header name to verify
-- @return the valid header name, or `nil+error`
_M.validate_header_name = function(name)
  if name == nil or name == "" then
    return nil, "no header name provided"
  end

  if re_match(name, "^[a-zA-Z0-9-_]+$", "jo") then
    return name
  end

  return nil, "bad header name '" .. name ..
              "', allowed characters are A-Z, a-z, 0-9, '_', and '-'"
end

--- Validates a cookie name.
-- Checks characters used in a cookie name to be valid
-- a-z, A-Z, 0-9, '_' and '-' are allowed.
-- @param name (string) the cookie name to verify
-- @return the valid cookie name, or `nil+error`
_M.validate_cookie_name = function(name)
  if name == nil or name == "" then
    return nil, "no cookie name provided"
  end

  if re_match(name, "^[a-zA-Z0-9-_]+$", "jo") then
    return name
  end

  return nil, "bad cookie name '" .. name ..
              "', allowed characters are A-Z, a-z, 0-9, '_', and '-'"
end


local validate_labels
do
  local nkeys = require "table.nkeys"

  local MAX_KEY_SIZE   = 63
  local MAX_VALUE_SIZE = 63
  local MAX_KEYS_COUNT = 10

  -- validation rules based on Kong Labels AIP
  -- https://kong-aip.netlify.app/aip/129/
  local BASE_PTRN = "[a-z0-9]([\\w\\.:-]*[a-z0-9]|)$"
  local KEY_PTRN  = "(?!kong)(?!konnect)(?!insomnia)(?!mesh)(?!kic)" .. BASE_PTRN
  local VAL_PTRN  = BASE_PTRN

  local function validate_entry(str, max_size, pattern)
    if str == "" or #str > max_size then
      return nil, fmt(
        "%s must have between 1 and %d characters", str, max_size)
    end
    if not re_match(str, pattern, "ajoi") then
      return nil, fmt("%s is invalid. Must match pattern: %s", str, pattern)
    end
    return true
  end

  -- Validates a label array.
  -- Validates labels based on the kong Labels AIP
  function validate_labels(raw_labels)
    if nkeys(raw_labels) > MAX_KEYS_COUNT then
      return nil, fmt(
        "labels validation failed: count exceeded %d max elements",
        MAX_KEYS_COUNT
      )
    end

    for _, kv in ipairs(raw_labels) do
      local del = kv:find(":", 1, true)
      local k = del and kv:sub(1, del - 1) or ""
      local v = del and kv:sub(del + 1) or ""

      local ok, err = validate_entry(k, MAX_KEY_SIZE, KEY_PTRN)
      if not ok then
        return nil, "label key validation failed: " .. err
      end
      ok, err = validate_entry(v, MAX_VALUE_SIZE, VAL_PTRN)
      if not ok then
        return nil, "label value validation failed: " .. err
      end
    end

    return true
  end
end
_M.validate_labels = validate_labels


---
-- Given an http status and an optional message, this function will
-- return a body that could be used in `kong.response.exit`.
--
-- * Status 204 will always return nil for the body
-- * 405, 500 and 502 always return a predefined message
-- * If there is a message, it will be used as a body
-- * Otherwise, there's a default body for 401, 404 & 503 responses
--
-- If after applying those rules there's a body, and that body isn't a
-- table, it will be transformed into one of the form `{ message = ... }`,
-- where `...` is the untransformed body.
--
-- This function throws an error on invalid inputs.
--
-- @tparam number status The status to be used
-- @tparam[opt] table|string message The message to be used
-- @tparam[opt] table headers The headers to be used
-- @return table|nil a possible body which can be used in kong.response.exit
-- @usage
--
-- --- 204 always returns nil
-- get_default_exit_body(204) --> nil
-- get_default_exit_body(204, "foo") --> nil
--
-- --- 405, 500 & 502 always return predefined values
--
-- get_default_exit_body(502, "ignored") --> { message = "Bad gateway" }
--
-- --- If message is a table, it is returned
--
-- get_default_exit_body(200, { ok = true }) --> { ok = true }
--
-- --- If message is not a table, it is transformed into one
--
-- get_default_exit_body(200, "ok") --> { message = "ok" }
--
-- --- 401, 404 and 503 provide default values if none is defined
--
-- get_default_exit_body(404) --> { message = "Not found" }
--
do
  local _overrides = {
    [405] = "Method not allowed",
    [500] = "An unexpected error occurred",
    [502] = "Bad gateway",
  }

  local _defaults = {
    [401] = "Unauthorized",
    [404] = "Not found",
    [503] = "Service unavailable",
  }

  local MIN_STATUS_CODE      = 100
  local MAX_STATUS_CODE      = 599

  function _M.get_default_exit_body(status, message)
    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if status == 204 then
      return nil
    end

    local body = _overrides[status] or message or _defaults[status]
    if body ~= nil and type(body) ~= "table" then
      body = { message = body }
    end

    return body
  end
end


local get_mime_type
local get_response_type
local get_error_template
do
  local CONTENT_TYPE_JSON    = "application/json"
  local CONTENT_TYPE_GRPC    = "application/grpc"
  local CONTENT_TYPE_HTML    = "text/html"
  local CONTENT_TYPE_XML     = "application/xml"
  local CONTENT_TYPE_PLAIN   = "text/plain"
  local CONTENT_TYPE_APP     = "application"
  local CONTENT_TYPE_TEXT    = "text"
  local CONTENT_TYPE_DEFAULT = "default"
  local CONTENT_TYPE_ANY     = "*"

  local MIME_TYPES = {
    [CONTENT_TYPE_GRPC]     = "",
    [CONTENT_TYPE_HTML]     = "text/html; charset=utf-8",
    [CONTENT_TYPE_JSON]     = "application/json; charset=utf-8",
    [CONTENT_TYPE_PLAIN]    = "text/plain; charset=utf-8",
    [CONTENT_TYPE_XML]      = "application/xml; charset=utf-8",
    [CONTENT_TYPE_APP]      = "application/json; charset=utf-8",
    [CONTENT_TYPE_TEXT]     = "text/plain; charset=utf-8",
    [CONTENT_TYPE_DEFAULT]  = "application/json; charset=utf-8",
  }

  local ERROR_TEMPLATES = {
    [CONTENT_TYPE_GRPC]   = "",
    [CONTENT_TYPE_HTML]   = [[
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Error</title>
  </head>
  <body>
    <h1>Error</h1>
    <p>%s.</p>
    <p>request_id: %s</p>
  </body>
</html>
]],
    [CONTENT_TYPE_JSON]   = [[
{
  "message":"%s",
  "request_id":"%s"
}]],
    [CONTENT_TYPE_PLAIN]  = "%s\nrequest_id: %s\n",
    [CONTENT_TYPE_XML]    = [[
<?xml version="1.0" encoding="UTF-8"?>
<error>
  <message>%s</message>
  <requestid>%s</requestid>
</error>
]],
  }

  local ngx_log = ngx.log
  local ERR     = ngx.ERR
  local custom_error_templates = setmetatable({}, {
    __index = function(self, format)
      local template_path = kong.configuration["error_template_" .. format]
      if not template_path then
        rawset(self, format, false)
        return false
      end

      local template, err
      if pl_path.exists(template_path) then
        template, err = pl_file.read(template_path)
      else
        err = "file not found"
      end

      if template then
        rawset(self, format, template)
        return template
      end

      ngx_log(ERR, fmt("failed reading the custom %s error template: %s", format, err))
      rawset(self, format, false)
      return false
    end
  })


  get_response_type = function(accept_header)
    local content_type = MIME_TYPES[CONTENT_TYPE_DEFAULT]
    if type(accept_header) == "table" then
      accept_header = join(",", accept_header)
    end

    if accept_header ~= nil then
      local pattern = [[
        ((?:[a-z0-9][a-z0-9-!#$&^_+.]+|\*) \/ (?:[a-z0-9][a-z0-9-!#$&^_+.]+|\*))
        (?:
          \s*;\s*
          q = ( 1(?:\.0{0,3}|) | 0(?:\.\d{0,3}|) )
          | \s*;\s* [a-z0-9][a-z0-9-!#$&^_+.]+ (?:=[^;]*|)
        )*
      ]]
      local accept_values = split(accept_header, ",")
      local max_quality = 0

      for _, accept_value in ipairs(accept_values) do
        accept_value = _M.strip(accept_value)
        local matches = ngx.re.match(accept_value, pattern, "ajoxi")

        if matches then
          local media_type = matches[1]
          local q = tonumber(matches[2]) or 1

          if q > max_quality then
            max_quality = q
            content_type = get_mime_type(media_type) or content_type
          end
        end
      end
    end

    return content_type
  end


  get_mime_type = function(content_header, use_default)
    use_default = use_default == nil or use_default
    content_header = _M.strip(content_header)
    content_header = _M.split(content_header, ";")[1]
    local mime_type

    local entries = split(content_header, "/")
    if #entries > 1 then
      if entries[2] == CONTENT_TYPE_ANY then
        if entries[1] == CONTENT_TYPE_ANY then
          mime_type = MIME_TYPES[CONTENT_TYPE_DEFAULT]
        else
          mime_type = MIME_TYPES[entries[1]]
        end
      else
        mime_type = MIME_TYPES[content_header]
      end
    end

    if mime_type or use_default then
      return mime_type or MIME_TYPES[CONTENT_TYPE_DEFAULT]
    end

    return nil, "could not find MIME type"
  end


  get_error_template = function(mime_type)
    if mime_type == CONTENT_TYPE_JSON or mime_type == MIME_TYPES[CONTENT_TYPE_JSON] then
      return custom_error_templates.json or ERROR_TEMPLATES[CONTENT_TYPE_JSON]

    elseif mime_type == CONTENT_TYPE_HTML or mime_type == MIME_TYPES[CONTENT_TYPE_HTML] then
      return custom_error_templates.html or ERROR_TEMPLATES[CONTENT_TYPE_HTML]

    elseif mime_type == CONTENT_TYPE_XML or mime_type == MIME_TYPES[CONTENT_TYPE_XML] then
      return custom_error_templates.xml or ERROR_TEMPLATES[CONTENT_TYPE_XML]

    elseif mime_type == CONTENT_TYPE_PLAIN or mime_type == MIME_TYPES[CONTENT_TYPE_PLAIN] then
      return custom_error_templates.plain or ERROR_TEMPLATES[CONTENT_TYPE_PLAIN]

    elseif mime_type == CONTENT_TYPE_GRPC or mime_type == MIME_TYPES[CONTENT_TYPE_GRPC] then
      return ERROR_TEMPLATES[CONTENT_TYPE_GRPC]

    end

    return nil, "no template found for MIME type " .. (mime_type or "empty")
  end

end
_M.get_mime_type = get_mime_type
_M.get_response_type = get_response_type
_M.get_error_template = get_error_template

--- Extract the parent domain of CN and CN itself from X509 certificate
-- @tparam resty.openssl.x509 x509 the x509 object to extract CN
-- @return cn (string) CN + parent (string) parent domain of CN, or nil+err if any
function _M.get_cn_parent_domain(x509)
  local name, err = x509:get_subject_name()
  if err then
    return nil, err
  end
  local cn, _, err = name:find("CN")
  if err then
    return nil, err
  end
  cn = cn.blob
  local parent = match(cn, "^[%a%d%*-]+%.(.+)$")
  return cn, parent
end


function _M.get_request_id()
  local ctx = ngx.ctx
  if ctx.admin_api then
    return ctx.admin_api.req_id
  end

  local ok, res = pcall(function() return ngx.var.set_request_id end)
  if ok and type(res) == "string" and res ~= "" then
    return res
  end

  return _M.random_string()
end


do
  local modules = {
    "kong.tools.table",
    "kong.tools.sha256",
    "kong.tools.yield",
    "kong.tools.string",
    "kong.tools.uuid",
    "kong.tools.rand",
    "kong.tools.system",
    "kong.tools.time",
    "kong.tools.ip",
  }

  for _, str in ipairs(modules) do
    local mod = require(str)
    for name, func in pairs(mod) do
      _M[name] = func
    end
  end
end


return _M
