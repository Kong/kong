local attribute_remover = {}

local function deep_copy(obj, seen)
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end

  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do
    res[deep_copy(k, s)] = deep_copy(v, s)
  end
  return res
end

local function split_string(source, separator)
  local result = { }
  for s in source:gmatch(separator) do
    result[#result + 1] = s
  end
  return result
end

local function delete_attribute(source, attribute)
  local table = source
  local segments = split_string(attribute, "([^.%s]+)")
  for i = 1, (#segments-1) do
    local segment = segments[i]
    if type(table[segment]) ~= 'table' then
      return
    end
    table = table[segment]
  end
  table[segments[#segments]] = nil
end

function attribute_remover.delete_attributes(source, attributes)
  source = deep_copy(source)
  for index, attribute in ipairs(attributes) do
    delete_attribute(source, attribute)
  end
  return source
end

return attribute_remover
