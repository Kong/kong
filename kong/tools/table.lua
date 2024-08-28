local type          = type
local pairs         = pairs
local ipairs        = ipairs
local select        = select
local tostring      = tostring
local insert        = table.insert
local setmetatable  = setmetatable
local getmetatable  = getmetatable


local _M = {}


_M.EMPTY = require("pl.tablex").readonly({})


--- packs a set of arguments in a table.
-- Explicitly sets field `n` to the number of arguments, so it is `nil` safe
_M.pack = function(...) return {n = select("#", ...), ...} end


--- unpacks a table to a list of arguments.
-- Explicitly honors the `n` field if given in the table, so it is `nil` safe
_M.unpack = function(t, i, j) return unpack(t, i or 1, j or t.n or #t) end


--- Merges two table together.
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.table_merge(t1, t2)
  local res = {}
  if t1 then
    for k,v in pairs(t1) do
      res[k] = v
    end
  end
  if t2 then
    for k,v in pairs(t2) do
      res[k] = v
    end
  end
  return res
end


--- Merges two table together but does not replace values from `t1` if `t2` for a given key has `ngx.null` value
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.null_aware_table_merge(t1, t2)
  local res = {}
  if t1 then
    for k,v in pairs(t1) do
      res[k] = v
    end
  end
  if t2 then
    for k,v in pairs(t2) do
      if res[k] == nil or v ~= ngx.null then
        res[k] = v
      end
    end
  end
  return res
end


--- Checks if a value exists in a table.
-- @param arr The table to use
-- @param val The value to check
-- @return Returns `true` if the table contains the value, `false` otherwise
function _M.table_contains(arr, val)
  if arr then
    for _, v in pairs(arr) do
      if v == val then
        return true
      end
    end
  end
  return false
end


do
  local floor = math.floor
  local max = math.max

  local is_array_fast = require "table.isarray"

  local is_array_strict = function(t)
    local m, c = 0, 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or floor(k) ~= k then
          return false
        end
        m = max(m, k)
        c = c + 1
    end
    return c == m
  end

  local is_array_lapis = function(t)
    if type(t) ~= "table" then
      return false
    end
    local i = 0
    for _ in pairs(t) do
      i = i + 1
      if t[i] == nil and t[tostring(i)] == nil then
        return false
      end
    end
    return true
  end

  --- Checks if a table is an array and not an associative array.
  -- @param t The table to check
  -- @param mode: `"strict"`: only sequential indices starting from 1 are allowed (no holes)
  --                `"fast"`: OpenResty optimized version (holes and negative indices are ok)
  --               `"lapis"`: Allows numeric indices as strings (no holes)
  -- @return Returns `true` if the table is an array, `false` otherwise
  function _M.is_array(t, mode)
    if type(t) ~= "table" then
      return false
    end

    if mode == "lapis" then
      return is_array_lapis(t)
    end

    if mode == "fast" then
      return is_array_fast(t)
    end

    return is_array_strict(t)
  end


  --- Checks if a table is an array and not an associative array.
  -- *** NOTE *** string-keys containing integers are considered valid array entries!
  -- @param t The table to check
  -- @return Returns `true` if the table is an array, `false` otherwise
  _M.is_lapis_array = is_array_lapis
end


--- Deep copies a table into a new table.
-- Tables used as keys are also deep copied, as are metatables
-- @param orig The table to copy
-- @param copy_mt Copy metatable (default is true)
-- @return Returns a copy of the input table
function _M.deep_copy(orig, copy_mt)
  if copy_mt == nil then
    copy_mt = true
  end
  local copy
  if type(orig) == "table" then
    copy = {}
    for orig_key, orig_value in next, orig, nil do
      copy[_M.deep_copy(orig_key)] = _M.deep_copy(orig_value, copy_mt)
    end
    if copy_mt then
      setmetatable(copy, _M.deep_copy(getmetatable(orig)))
    end
  else
    copy = orig
  end
  return copy
end


do
  local clone = require "table.clone"

  --- Copies a table into a new table.
  -- neither sub tables nor metatables will be copied.
  -- @param orig The table to copy
  -- @return Returns a copy of the input table
  function _M.shallow_copy(orig)
    local copy
    if type(orig) == "table" then
      copy = clone(orig)
    else -- number, string, boolean, etc
      copy = orig
    end
    return copy
  end
end


--- Merges two tables recursively
-- For each sub-table in t1 and t2, an equivalent (but different) table will
-- be created in the resulting merge. If t1 and t2 have a sub-table with the
-- same key k, res[k] will be a deep merge of both sub-tables.
-- Metatables are not taken into account.
-- Keys are copied by reference (if tables are used as keys they will not be
-- duplicated)
-- @param t1 one of the tables to merge
-- @param t2 one of the tables to merge
-- @return Returns a table representing a deep merge of the new table
function _M.deep_merge(t1, t2)
  local res = _M.deep_copy(t1)

  for k, v in pairs(t2) do
    if type(v) == "table" and type(res[k]) == "table" then
      res[k] = _M.deep_merge(res[k], v)
    else
      res[k] = _M.deep_copy(v) -- returns v when it is not a table
    end
  end

  return res
end


--- Cycle aware deep copies a table into a new table.
-- Cycle aware means that a table value is only copied once even
-- if it is referenced multiple times in input table or its sub-tables.
-- Tables used as keys are not deep copied. Metatables are set to same
-- on copies as they were in the original.
-- @param orig The table to copy
-- @param remove_metatables Removes the metatables when set to `true`.
-- @param deep_copy_keys Deep copies the keys (and not only the values) when set to `true`.
-- @param cycle_aware_cache Cached tables that are not copied (again).
--                          (the function creates this table when not given)
-- @return Returns a copy of the input table
function _M.cycle_aware_deep_copy(orig, remove_metatables, deep_copy_keys, cycle_aware_cache)
  if type(orig) ~= "table" then
    return orig
  end

  cycle_aware_cache = cycle_aware_cache or {}
  if cycle_aware_cache[orig] then
    return cycle_aware_cache[orig]
  end

  local copy = _M.shallow_copy(orig)

  cycle_aware_cache[orig] = copy

  local mt
  if not remove_metatables then
    mt = getmetatable(orig)
  end

  for k, v in pairs(orig) do
    if type(v) == "table" then
      copy[k] = _M.cycle_aware_deep_copy(v, remove_metatables, deep_copy_keys, cycle_aware_cache)
    end

    if deep_copy_keys and type(k) == "table" then
      local new_k = _M.cycle_aware_deep_copy(k, remove_metatables, deep_copy_keys, cycle_aware_cache)
      copy[new_k] = copy[k]
      copy[k] = nil
    end
  end

  if mt then
    setmetatable(copy, mt)
  end

  return copy
end


--- Cycle aware merges two tables recursively
-- The table t1 is deep copied using cycle_aware_deep_copy function.
-- The table t2 is deep merged into t1. The t2 values takes precedence
-- over t1 ones. Tables used as keys are not deep copied. Metatables
-- are set to same on copies as they were in the original.
-- @param t1 one of the tables to merge
-- @param t2 one of the tables to merge
-- @param remove_metatables Removes the metatables when set to `true`.
-- @param deep_copy_keys Deep copies the keys (and not only the values) when set to `true`.
-- @param cycle_aware_cache Cached tables that are not copied (again)
--                          (the function creates this table when not given)
-- @return Returns a table representing a deep merge of the new table
function _M.cycle_aware_deep_merge(t1, t2, remove_metatables, deep_copy_keys, cycle_aware_cache)
  cycle_aware_cache = cycle_aware_cache or {}
  local merged = _M.cycle_aware_deep_copy(t1, remove_metatables, deep_copy_keys, cycle_aware_cache)
  for k, v in pairs(t2) do
    if type(v) == "table" then
      if type(merged[k]) == "table" then
        merged[k] = _M.cycle_aware_deep_merge(merged[k], v, remove_metatables, deep_copy_keys, cycle_aware_cache)
      else
        merged[k] = _M.cycle_aware_deep_copy(v, remove_metatables, deep_copy_keys, cycle_aware_cache)
      end
    else
      merged[k] = v
    end
  end
  return merged
end


--- Concatenates lists into a new table.
function _M.concat(...)
  local result = {}
  for _, t in ipairs({...}) do
    for _, v in ipairs(t) do insert(result, v) end
  end
  return result
end


local err_list_mt = {}


--- Add an error message to a key/value table.
-- If the key already exists, a sub table is created with the original and the new value.
-- @param errors (Optional) Table to attach the error to. If `nil`, the table will be created.
-- @param k Key on which to insert the error in the `errors` table.
-- @param v Value of the error
-- @return The `errors` table with the new error inserted.
function _M.add_error(errors, k, v)
  if not errors then
    errors = {}
  end

  if errors and errors[k] then
    if getmetatable(errors[k]) ~= err_list_mt then
      errors[k] = setmetatable({errors[k]}, err_list_mt)
    end

    insert(errors[k], v)
  else
    errors[k] = v
  end

  return errors
end


--- Retrieves a value from table using path.
-- @param t The source table to retrieve the value from.
-- @param path Path table containing keys
-- @return Returns `value` if something was found and `nil` otherwise
function _M.table_path(t, path)
  local current_value = t
  for _, path_element in ipairs(path) do
    if current_value[path_element] == nil then
      return nil
    end

    current_value = current_value[path_element]
  end

  return current_value
end


return _M
