local char = string.char
local gsub = string.gsub

local match        = string.match
local unescape_uri = ngx.unescape_uri
local escape_uri   = ngx.escape_uri
local pairs = pairs
local type = type
local tostring = tostring
local next = next
local setmetatable = setmetatable
local table_insert = table.insert
local table_sort   = table.sort
local table_concat = table.concat

local NULL                = "\0"
local TRACE_ID_SIZE_BYTES = 16
local SPAN_ID_SIZE_BYTES  = 8

local FORMATS = {
  W3C       = "w3c",
  B3        = "b3",
  B3_SINGLE = "b3-single",
  JAEGER    = "jaeger",
  OT        = "ot",
  DATADOG   = "datadog",
  AWS       = "aws",
  GCP       = "gcp",
  INSTANA   = "instana",
  MCP       = "mcp",
}

local function hex_to_char(c)
  return char(tonumber(c, 16))
end

local function from_hex(str)
  if type(str) ~= "string" then
    return nil, "not a string"
  end

  if #str % 2 ~= 0 then
    str = "0" .. str
  end

  if str ~= nil then
    str = gsub(str, "%x%x", hex_to_char)
  end
  return str
end

local baggage_mt = {
  __newindex = function()
    error("attempt to set immutable baggage", 2)
  end,
}

local function parse_baggage_headers(headers, header_pattern)
  local baggage
  for k, v in pairs(headers) do
    local baggage_key = match(k, header_pattern)
    if baggage_key then
      if baggage then
        baggage[baggage_key] = unescape_uri(v)
      else
        baggage = { [baggage_key] = unescape_uri(v) }
      end
    end
  end

  if baggage then
    return setmetatable(baggage, baggage_mt)
  end
end

local function parse_w3c_baggage(baggage_raw)
  if not baggage_raw then
    return nil
  end

  local baggage
  if type(baggage_raw) == "table" then
    for k, v in pairs(baggage_raw) do
      if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
        if not baggage then
          baggage = {}
        end
        baggage[k] = tostring(v)
      end
    end
  elseif type(baggage_raw) == "string" then
    for item in baggage_raw:gmatch("[^,]+") do
      item = item:match("^%s*(.-)%s*$")
      if item and item ~= "" then
        local key_val = item:match("^([^;]+)")
        if key_val then
          local k, v = key_val:match("^%s*([^=]+)%s*=%s*(.-)%s*$")
          if k and v then
            if not baggage then
              baggage = {}
            end
            baggage[unescape_uri(k)] = unescape_uri(v)
          end
        end
      end
    end
  end

  if baggage and next(baggage) ~= nil then
    return setmetatable(baggage, baggage_mt)
  end
end

local function format_w3c_baggage(baggage)
  if not baggage or type(baggage) ~= "table" or next(baggage) == nil then
    return nil
  end

  local items = {}
  for k, v in pairs(baggage) do
    if type(k) == "string" and v ~= nil then
      table_insert(items, escape_uri(k) .. "=" .. escape_uri(tostring(v)))
    end
  end

  if #items == 0 then
    return nil
  end

  table_sort(items)
  return table_concat(items, ",")
end

local function to_id_size(id, length)
  if not id then
    return nil
  end

  local len = #id
  if len > length then
    return id:sub(-length)

  elseif len < length then
    return NULL:rep(length - len) .. id
  end

  return id
end

local function to_kong_trace_id(id)
  return to_id_size(id, TRACE_ID_SIZE_BYTES)
end

local function to_kong_span_id(id)
  return to_id_size(id, SPAN_ID_SIZE_BYTES)
end

return {
  FORMATS = FORMATS,

  from_hex = from_hex,
  to_id_size = to_id_size,
  to_kong_trace_id = to_kong_trace_id,
  to_kong_span_id = to_kong_span_id,
  parse_baggage_headers = parse_baggage_headers,
  parse_w3c_baggage = parse_w3c_baggage,
  format_w3c_baggage = format_w3c_baggage,
}
