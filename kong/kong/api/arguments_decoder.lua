local getmetatable = getmetatable
local tonumber     = tonumber
local rawget       = rawget
local insert       = table.insert
local unpack       = table.unpack       -- luacheck: ignore table
local ipairs       = ipairs
local pairs        = pairs
local type         = type
local ngx          = ngx
local req          = ngx.req
local log          = ngx.log
local re_match     = ngx.re.match
local re_gmatch    = ngx.re.gmatch
local re_gsub      = ngx.re.gsub
local get_method   = req.get_method


local NOTICE       = ngx.NOTICE

local ENC_LEFT_SQUARE_BRACKET = "%5B"
local ENC_RIGHT_SQUARE_BRACKET = "%5D"


local multipart_mt = {}


function multipart_mt:__tostring()
  return self.data
end


function multipart_mt:__index(name)
  local json = rawget(self, "json")
  if json then
    return json[name]
  end

  return nil
end


-- Extracts keys from a string representing a nested table
-- e.g. [foo][bar][21].key => ["foo", "bar", 21, "key"].
-- is_map is meant to label patterns that use the bracket map syntax.
local function extract_param_keys(keys_string)
  local is_map = false

  -- iterate through keys (split by dots or square brackets)
  local iterator, err = re_gmatch(keys_string, [=[\.([^\[\.]+)|\[([^\]]*)\]]=], "jos")
  if not iterator then
    return nil, err
  end

  local keys = {}
  for captures, it_err in iterator do
    if it_err then
      log(NOTICE, it_err)

    else
      local key_name
      if captures[1] then
        -- The first capture: `\.([^\[\.]+)` matches dot-separated keys
        key_name = captures[1]

      else
        -- The second capture: \[([^\]]*)\] matches bracket-separated keys
        key_name = captures[2]

        -- If a bracket-separated key is non-empty and non-numeric, set
        -- is_map to true: foo[test] is a map, foo[] and bar[42] are arrays
        local map_key_found = key_name ~= "" and tonumber(key_name) == nil
        if map_key_found then
          is_map = true
        end
      end

      insert(keys, key_name)
    end
  end

  return keys, nil, is_map
end


-- Extracts the parameter name and keys from a string
-- e.g. myparam[foo][bar][21].key => myparam, ["foo", "bar", 21, "key"]
local function get_param_name_and_keys(name_and_keys)
  -- key delimiter must appear after the first character
  -- e.g. for `[5][foo][bar].key`, `[5]` is the parameter name
  local first_key_delimiter = name_and_keys:find('[%[%.]', 2)
  if not first_key_delimiter then
    return nil, "keys not found"
  end

  local param_name = name_and_keys:sub(1, first_key_delimiter - 1)
  local keys_string = name_and_keys:sub(first_key_delimiter)

  local keys, err, is_map = extract_param_keys(keys_string)
  if not keys then
    return nil, err
  end

  return param_name, nil, keys, is_map
end


-- Nests the provided path into container
-- e.g. nest_path({}, {"foo", "bar", 21, "key"}, 42) => { foo = { bar = { [21] = { key = 42 } } } }
local function nest_path(container, path, value)
  container = container or {}

  if type(path) ~= "table" then
    return nil, "path must be a table"
  end

  for i = 1, #path do
    local segment = path[i]

    local arr_index = tonumber(segment)
    -- if it looks like: foo[] or bar[42], it's an array
    local isarray = segment == "" or arr_index ~= nil

    if isarray then
      if i == #path then

        if arr_index then
          insert(container, arr_index, value)
          return container[arr_index]
        end

        if type(value) == "table" and getmetatable(value) ~= multipart_mt then
          for j, v in ipairs(value) do
            insert(container, j, v)
          end

          return container
        end

        container[#container + 1] = value
        return container

      else
        local position = arr_index or 1
        if not container[position] then
          container[position] = {}
          container = container[position]
        end
      end

    else -- it's a map
      if i == #path then
        container[segment] = value
        return container[segment]

      elseif not container[segment] then
        container[segment] = {}
        container = container[segment]
      end
    end
  end
end


-- Decodes a complex argument (map, array or mixed), into a nested table
-- e.g. foo[bar][21].key, 42 => { foo = { bar = { [21] = { key = 42 } } } }
local function decode_map_array_arg(name, value, container)
  local param_name, err, keys, is_map = get_param_name_and_keys(name)
  if not param_name or not keys or #keys == 0 then
    return nil, err or "not a map or array"
  end

  -- the meaning of square brackets varies depending on the http method.
  -- It is considered a map when a non numeric value exists between brackets
  -- if the method is POST, PUT, or PATCH, otherwise it is interpreted as LHS
  -- brackets used for search capabilities (only in EE).
  if is_map then
    local method = get_method()
    if method ~= "POST" and method ~= "PUT" and method ~= "PATCH" then
      return nil, "map not supported for this method"
    end
  end

  local path = {param_name, unpack(keys)}
  return nest_path(container, path, value)
end


local function decode_complex_arg(name, value, container)
  container = container or {}

  if type(name) ~= "string" then
    container[name] = value
    return container[name]
  end

  local decoded = decode_map_array_arg(name, value, container)
  if not decoded then
    container[name] = value
    return container[name]
  end

  return decoded
end


local function decode_arg(raw_name, value)
  if type(raw_name) ~= "string" or re_match(raw_name, [[^\.+|\.$]], "jos") then
    return { name = value }
  end

  -- unescape `[` and `]` characters when the array / map syntax is detected
  local array_map_pattern = ENC_LEFT_SQUARE_BRACKET .. "(.*?)" .. ENC_RIGHT_SQUARE_BRACKET
  local name = re_gsub(raw_name, array_map_pattern, "[$1]", "josi")

  -- treat test[foo.bar] as a single match instead of splitting on the dot
  local iterator, err = re_gmatch(name, [=[([^.](?:\[[^\]]*\])*)+]=], "jos")
  if not iterator then
    if err then
      log(NOTICE, err)
    end

    return decode_complex_arg(name, value)
  end

  local names = {}
  local count = 0

  while true do
    local captures, err = iterator()
    if captures then
      count = count + 1
      names[count] = captures[0]

    elseif err then
      log(NOTICE, err)
      break

    else
      break
    end
  end

  if count == 0 then
    return decode_complex_arg(name, value)
  end

  local container = {}
  local bucket = container

  for i = 1, count do
    if i == count then
      decode_complex_arg(names[i], value, bucket)
      return container

    else
      bucket = decode_complex_arg(names[i], {}, bucket)
    end
  end
end


local function decode(args)
  local i = 0
  local r = {}

  if type(args) ~= "table" then
    return r
  end

  for name, value in pairs(args) do
    i = i + 1
    r[i] = decode_arg(name, value)
  end

  return r
end


return {
  decode       = decode,
  multipart_mt = multipart_mt,
  _decode_arg  = decode_arg,
  _extract_param_keys = extract_param_keys,
  _get_param_name_and_keys = get_param_name_and_keys,
  _nest_path = nest_path,
  _decode_map_array_arg = decode_map_array_arg,
}
