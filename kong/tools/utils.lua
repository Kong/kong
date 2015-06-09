local uuid = require "uuid"

-- This is important to seed the UUID generator
uuid.seed()

local _M = {}

-- Generates a random unique string
-- @param `no_hypens` (Optional) optionally remove hypens from the output
-- @return `string`   The random string
function _M.random_string()
  local res = uuid()
  return res:gsub("-", "")
end

-- Calculates a table size
-- @param `t`       The table to use
-- @return `number` The size
function _M.table_size(t)
  local res = 0
  for _ in pairs(t) do
    res = res + 1
  end
  return res
end

-- Merges two table together
-- @param `t1`      The first table
-- @param `t2`      The second table
-- @return `table`  The final table
function _M.table_merge(t1, t2)
  local res = {}
  for k,v in pairs(t1) do res[k] = v end
  for k,v in pairs(t2) do res[k] = v end
  return res
end

-- Checks if a value exists in a table
-- @param `arr`      The table to use
-- @param `val`      The value to check
-- @return `boolean` Returns true if the table contains the value
function _M.table_contains(arr, val)
  for _, v in pairs(arr) do
    if v == val then
      return true
    end
  end
  return false
end

-- Checks if a table is an array and not an associative array
-- @param `t`        The table to use
-- @return `boolean` Returns true if the table is an array
function _M.is_array(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil and t[tostring(i)] == nil then return false end
  end
  return true
end

-- Deep copies a table into another table
-- @param `orig`     The table to copy
-- @return `table`   Returns a copy of the input table
function _M.deep_copy(orig)
  local copy
  if type(orig) == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[_M.deep_copy(orig_key)] = _M.deep_copy(orig_value)
    end
    setmetatable(copy, _M.deep_copy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end


-- Add an error message to a key/value table.
-- Can accept a nil argument, and if is nil, will initialize the table.
-- @param `errors`  (Optional) Can be nil. Table to attach the error to. If nil, the table will be created.
-- @param `k`       Key on which to insert the error in the `errors` table.
-- @param `v`       Value of the error
-- @return `errors` The `errors` table with the new error inserted.
function _M.add_error(errors, k, v)
  if not errors then errors = {} end

  if errors and errors[k] then
    local list = {}
    table.insert(list, errors[k])
    table.insert(list, v)
    errors[k] = list
  else
    errors[k] = v
  end

  return errors
end

-- Try to load a module and do not throw an error if the module was not found.
-- Will throw an error if the loading failed for another reason (ex: syntax error).
-- @param `module_name` Path of the module to load (ex: kong.plugins.keyauth.api).
-- @return `loaded`     A boolean indicating wether the module was successfully loaded or not.
-- @return `module`     The retrieved module (not loaded).
function _M.load_module_if_exists(module_name)
  local status, res = pcall(require, module_name)
  if status then
    return true, res
  -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
  elseif type(res) == "string" and string.find(res, "module '.*' not found") then
    return false
  else
    error(res)
  end
end

return _M
