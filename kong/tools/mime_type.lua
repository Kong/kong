local lpeg = require "lpeg"
local clear_tab = require "table.clear"

local P, S, R, C = lpeg.P, lpeg.S, lpeg.R, lpeg.C
local ipairs = ipairs
local lower = string.lower
local EMPTY = {}

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
  if #args == 1 and args[1] == "*" then
    return "*", "*"
  end
  return ...
end

-- cached vars
local param_key_ignorecase
local ignorecase_params = {}

local merge_params = function(...)
  local params = {}
  local key

  for _, v in ipairs{...} do
    if key then
      local lowercase_key = lower(key)
      if param_key_ignorecase or ignorecase_params[lowercase_key] then
        key = lowercase_key
      end
      params[key] = v
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
-- @tparam[opt] table opts A optional options to be used
-- @treturn string|string|table Returns type, subtype, params
-- @treturn nil|nil|nil Invalid mime-type
-- @usage
-- -- application, json, { charset = "utf-8", q = "1" }
-- parse_mime_type("application/json; charset=utf-8; q=1")
-- -- application, json, { charset = "utf-8", key = "Value" }
-- parse_mime_type("application/json; Charset=utf-8; Key=Value", { param_key_ignorecase = true } )
-- -- application, json, { charset = "utf-8", Key = "Value" }
-- parse_mime_type("application/json; Charset=utf-8; Key=Value", { ignorecase_params = { "charset" } } )
local function parse_mime_type(mime_type, opts)
  opts = opts or EMPTY

  param_key_ignorecase = opts.param_key_ignorecase
  clear_tab(ignorecase_params)
  if not param_key_ignorecase then
    for _, param in ipairs(opts.ignorecase_params or EMPTY) do
      ignorecase_params[param] = true
    end
  end

  return media_type:match(mime_type)
end


return {
  parse_mime_type = parse_mime_type
}
