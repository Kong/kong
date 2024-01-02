local _S = {}

-- imports
local sha256        = require "resty.sha256"
local encode_base64 = ngx.encode_base64
local fmt           = string.format
local cjson         = require("cjson.safe")
--

-- globals
local GMATCH_PATTERN = "{{(.*?)}}"
local GSUB_REPLACE_PATTERN = "{{([%w_]+)}}"
--


local function deepcopy(o, seen)
  seen = seen or {}
  if o == nil then return nil end
  if seen[o] then return seen[o] end

  local no
  if type(o) == 'table' then
    no = {}
    seen[o] = no

    for k, v in next, o, nil do
      no[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    setmetatable(no, deepcopy(getmetatable(o), seen))
  else -- number, string, boolean, etc
    no = o
  end
  return no
end


local function hash_template(template_table)
  local template_string, err = cjson.encode(template_table)
  if err then return nil, err end

  local template_hash = sha256:new()
  template_hash:update(template_string or '')
  return fmt("SHA-256=%s", encode_base64(template_hash:final())), nil
end

local function backslash_replacement_function(c)
  if c == "\n" then
     return "\\n"
  elseif c == "\r" then
     return "\\r"
  elseif c == "\t" then
     return "\\t"
  elseif c == "\b" then
     return "\\b"
  elseif c == "\f" then
     return "\\f"
  elseif c == '"' then
     return '\\"'
  elseif c == '\\' then
     return '\\\\'
  else
     return string.format("\\u%04x", c:byte())
  end
end

-- borrowed from turbo-json
local function sanitize_parameter(s)
  if type(s) ~= "string" or s == "" then
    return nil, nil, "only string arguments are supported"
  end

  local chars_to_be_escaped_in_JSON_string
  = '['
  ..    '"'    -- class sub-pattern to match a double quote
  ..    '%\\'  -- class sub-pattern to match a backslash
  ..    '%z'   -- class sub-pattern to match a null
  ..    '\001' .. '-' .. '\031' -- class sub-pattern to match control characters
  .. ']'

  -- check if someone is trying to inject JSON control characters to close the command
  if s:sub(-1) == "," then
    s = s:sub(1, -1)
  end

  return s:gsub(chars_to_be_escaped_in_JSON_string, backslash_replacement_function), nil
end

function _S:new()
  local o = o or {}
  setmetatable(o, self)
  self.__index = self

  return o
end


function _S:render(template, request_type, properties)
  local sanitized_properties = {}
  local err, _
  for k, v in pairs(properties) do
    sanitized_properties[k], _, err = sanitize_parameter(v)
    if err then return nil, err end
  end

  local result = template.template:gsub(GSUB_REPLACE_PATTERN, sanitized_properties)
  
  -- find any missing variables
  local errors = {}
  local error_string
  for w in (result .. ";"):gmatch(GSUB_REPLACE_PATTERN) do 
    errors[w] = true
  end

  if not (next(errors) == nil) then
    for k, _ in pairs(errors) do
      if not error_string then
        error_string = fmt("missing template parameters: [%s]", k)
      else
        error_string = fmt("%s, [%s]", error_string, k)
      end
    end
  end

  return result, error_string
end

return _S
