local pl_string = require "pl.stringx"
local utils = require "kong.tools.utils"
local tablex      = require "pl.tablex"
local cjson = require "cjson"

local type = type
local pairs = pairs
local remove = table.remove


local _M = {}

-- Parses a form value, handling multipart/data values
-- @param `v` The value object
-- @return The parsed value
local function parse_value(v)
  return type(v) == "table" and v.content or v -- Handle multipart
end

-- Put nested keys in objects:
-- Normalize dotted keys in objects.
-- Example: {["key.value.sub"]=1234} becomes {key = {value = {sub=1234}}
-- @param `obj` Object to normalize
-- @return `normalized_object`
function _M.normalize_nested_params(obj)
  local new_obj = {}

  local function attach_dotted_key(keys, attach_to, value)
    local current_key = keys[1]

    if #keys > 1 then
      if not attach_to[current_key] then
        attach_to[current_key] = {}
      end
      remove(keys, 1)
      attach_dotted_key(keys, attach_to[current_key], value)
    else
      attach_to[current_key] = value
    end
  end

  for k, v in pairs(obj) do
    if type(v) == "table" then
      -- normalize arrays since Lapis parses ?key[1]=foo as {["1"]="foo"} instead of {"foo"}
      if utils.is_array(v) then
        local arr = {}
        for _, arr_v in pairs(v) do arr[#arr+1] = arr_v end
        v = arr
      else
        v = _M.normalize_nested_params(v) -- recursive call on other table values
      end
    end

    -- normalize sub-keys with dot notation
    if type(k) == "string" then
      local keys = pl_string.split(k, ".")
      if #keys > 1 then -- we have a key containing a dot
        attach_dotted_key(keys, new_obj, parse_value(v))

      else
        new_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
      end

    else
      new_obj[k] = parse_value(v) -- nothing special with that key, simply attaching the value
    end
  end

  return new_obj
end


-- Remove functions from a schema definition so that
-- cjson can encode the schema.
local schema_to_jsonable
do
  local insert = table.insert
  local ipairs = ipairs
  local next = next

  local fdata_to_jsonable


  local function fields_to_jsonable(fields)
    local out = {}
    for _, field in ipairs(fields) do
      local fname = next(field)
      local fdata = field[fname]
      insert(out, { [fname] = fdata_to_jsonable(fdata, "no") })
    end
    setmetatable(out, cjson.array_mt)
    return out
  end


  -- Convert field data from schemas into something that can be
  -- passed to a JSON encoder.
  -- @tparam table fdata A Lua table with field data
  -- @tparam string is_array A three-state enum: "yes", "no" or "maybe"
  -- @treturn table A JSON-convertible Lua table
  fdata_to_jsonable = function(fdata, is_array)
    local out = {}
    local iter = is_array == "yes" and ipairs or pairs

    for k, v in iter(fdata) do
      if is_array == "maybe" and type(k) ~= "number" then
        is_array = "no"
      end

      if k == "schema" then
        out[k] = schema_to_jsonable(v)

      elseif type(v) == "table" then
        if k == "fields" and fdata.type == "record" then
          out[k] = fields_to_jsonable(v)

        elseif k == "default" and fdata.type == "array" then
          out[k] = fdata_to_jsonable(v, "yes")

        else
          out[k] = fdata_to_jsonable(v, "maybe")
  end

      elseif type(v) == "number" then
        if v ~= v then
          out[k] = "nan"
        elseif v == math.huge then
          out[k] = "inf"
        elseif v == -math.huge then
          out[k] = "-inf"
        else
          out[k] = v
  end

      elseif type(v) ~= "function" then
        out[k] = v
      end
    end
    if is_array == "yes" or is_array == "maybe" then
      setmetatable(out, cjson.array_mt)
    end
    return out
  end


  schema_to_jsonable = function(schema)
    local fields = fields_to_jsonable(schema.fields)
    return { fields = fields }
  end
  _M.schema_to_jsonable = schema_to_jsonable
end


function _M.NEEDS_BODY(method)
  return tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })[method]
end


return _M
