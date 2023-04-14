local lpeg = require "lpeg"

local P, S, R, C = lpeg.P, lpeg.S, lpeg.R, lpeg.C
local ipairs = ipairs
local lower = string.lower
local sub = string.sub
local find = string.find
local type = type
local error = error

local WILDCARD = "*"

--[[
RFC2045(https://www.ietf.org/rfc/rfc2045.txt)

media-type     = type "/" subtype *(";" parameter )
parameter      = attribute "=" value
attribute      = token
value          = token | quoted-string
quoted-string  = ( <"> *(qdtext | quoted-pair ) <"> )
qdtext         = <any TEXT except <">>
quoted-pair    = "\" CHAR
type           = token
subtype        = token
token          = 1*<any CHAR except CTLs or separators>
CHAR           = <any US-ASCII character (octets 0 - 127)>
separators     = "(" | ")" | "<" | ">" | "@"
               | "," | ";" | ":" | "\" | <">
               | "/" | "[" | "]" | "?" | "="
               | "{" | "}" | SP | HT
CTL            = <any US-ASCII ctl chr (0-31) and DEL (127)>
]]--

local CTL = R"\0\31" + P"\127"
local CHAR = R"\0\127"
local quote = P'"'
local separators = S"()<>@,;:\\\"/[]?={} \t"
local token = (CHAR - CTL - separators)^1
local spacing = (S" \t")^0

local qdtext = P(1) - CTL - quote
local quoted_pair = P"\\" * CHAR
local quoted_string = quote * C((qdtext + quoted_pair)^0) * quote

local attribute = C(token)
local value = C(token) + quoted_string
local parameter = attribute * P"=" * value
local parameters = (spacing * P";" * spacing * parameter)^0
local types = C(token) * P"/" * C(token) + C"*"

local function format_types(...)
  local args = {...}
  local nargs = #args
  if nargs == 1 and args[1] == "*" then
    return "*", "*"
  end
  for i=1, nargs do
    args[i] = lower(args[i])
  end
  return unpack(args)
end


local merge_params = function(...)
  local params = {}
  local key

  for _, v in ipairs{...} do
    if key then
      local lowercase_key = lower(key)
      params[lowercase_key] = v
      key = nil

    else
      key = v
    end
  end

  return params
end

local media_type = (types/format_types) * (parameters/merge_params) * P(-1)

--- Parses mime-type
-- @tparam string mime_type The mime-type to be parsed
-- @treturn string|string|table Returns type, subtype, params
-- @treturn nil|nil|nil Invalid mime-type
-- @usage
-- -- application, json, { charset = "utf-8", q = "1" }
-- parse_mime_type("application/json; charset=utf-8; q=1")
-- -- application, json, { charset = "utf-8", key = "Value" }
-- parse_mime_type("application/json; Charset=utf-8; Key=Value")
local function parse_mime_type(mime_type)
  return media_type:match(mime_type)
end

--- Checks if this mime-type includes other mime-type
-- @tparam table this This mime-type
-- @tparam table other Other mime-type
-- @treturn boolean Returns `true` if this mime-type includes other, `false` otherwise
local function includes(this, other)
  if type(this) ~= "table" then
    error("this must be a table", 2)
  end
  if type(other) ~= "table" then
    error("other must be a table", 2)
  end

  local this_type = this.type
  local this_subtype = this.subtype
  local other_type = other.type
  local other_subtype = other.subtype

  if this_type == WILDCARD then
    -- */* includes anything
    return true
  end

  if this_type == other_type then
    if this_subtype == other_subtype or this_subtype == WILDCARD then
      return true
    end

    if sub(this_subtype, 1, 2) == "*+" then
      -- subtype is wildcard with suffix, e.g. *+json
      local this_subtype_suffix = sub(this.subtype, 3)
      local pattern = "^.-+" .. this_subtype_suffix ..  "$"
      if find(other_subtype, pattern) then
        return true
      end
    end
  end

  return false
end

return {
  parse_mime_type = parse_mime_type,
  includes = includes,
}
