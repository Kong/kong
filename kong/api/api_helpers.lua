local utils = require "kong.tools.utils"
local tablex      = require "pl.tablex"
local cjson = require "cjson"

local type = type
local pairs = pairs


local _M = {}

-- Parses a form value, handling multipart/data values
-- @param `v` The value object
-- @return The parsed value
local function parse_value(v)
  return type(v) == "table" and v.content or v -- Handle multipart
end

local NO_ARRAY_INDEX_MARK = {}

-- given a string like "x[1].y", return an array of indices like {"x", 1, "y"}
-- the path parameter is an output-only param. the keys are added to it in order
local function key_to_path(key, path)
  -- try to match an array access like x[1].
  -- the left side of the [] is mandatory
  -- the array index can be omitted (the key will look like x[]).
  -- if that's the case we mark the path entry with a special key
  local left, array_index = key:match("^(.+)%[(%d*)]$")
  if left then
    key_to_path(left, path)
    path[#path + 1] = tonumber(array_index) or NO_ARRAY_INDEX_MARK
    return path
  end

  -- if no match, try a hash access like x.y (both x and y are mandatory)
  -- the left side of the dot is called left and the other side is right
  local left, right = key:match("^(.+)%.(.+)$")
  if left then
    key_to_path(left, path)
    key_to_path(right, path)
    return path
  end

  -- if no match found, append the whole key to the path as a single string
  path[#path + 1] = key
  return path
end

-- when NO_ARRAY_INDEX is encountered, replace it with the length of the node being parsed
local function transform_no_array_index_mark(path_entry, node)
  if path_entry == NO_ARRAY_INDEX_MARK then
    return #node + 1
  end
  return path_entry
end


-- Put nested keys in objects:
-- Normalize dotted keys in objects.
-- Example: {["key.value.sub"]=1234} becomes {key = {value = {sub=1234}}
-- @param `obj` Object to normalize
-- @return `normalized_object`
function _M.normalize_nested_params(obj)
  local new_obj = {}
  local is_array

  for k, v in pairs(obj) do
    is_array = false
    if type(v) == "table" then
      -- normalize arrays since Lapis parses ?key[1]=foo as {["1"]="foo"} instead of {"foo"}
      if utils.is_array(v) then
        is_array = true
        local arr = {}
        for _, arr_v in pairs(v) do arr[#arr+1] = arr_v end
        v = arr
      else
        v = _M.normalize_nested_params(v) -- recursive call on other table values
      end
    end

    v = parse_value(v)

    -- normalize sub-keys with hash or array accesses
    if type(k) == "string" then
      local path = key_to_path(k, {})
      local path_len = #path
      local node = new_obj
      local prev = new_obj
      local path_entry
      -- create any missing tables when dealing with x.foo[1].y = "bar"
      for i = 1, path_len - 1 do
        path_entry = transform_no_array_index_mark(path[i], node)
        node[path_entry] = node[path_entry] or {}
        prev = node
        node = node[path_entry]
      end

      -- on the last item of the path (the "y" in the example above)
      if path[path_len] == NO_ARRAY_INDEX_MARK and is_array then
        -- edge case: we are assigning an array to a no-array index mark: x[] = {1,2,3}
        -- on this case we backtrack one element (we use `prev` instead of `node`)
        -- and we set it to the array (v)
        -- this edge case is needed because Lapis builds params like that (flatten_params function)
        prev[path_entry or k] = v
      else
        -- regular case: the last element is similar to the loop iteration.
        -- instead of a table, we set the value (v) on the last element
        node[transform_no_array_index_mark(path[path_len], node)] = v
      end
    else
      new_obj[k] = v -- nothing special with that key, simply attaching the value
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
