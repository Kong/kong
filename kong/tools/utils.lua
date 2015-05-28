local _M = {}

function _M.table_size(t)
  local res = 0
  for _,_ in pairs(t) do
    res = res + 1
  end
  return res
end

function _M.is_empty(t)
  return next(t) == nil
end

_M.sort = {
  descending = function(a, b) return a > b end,
  ascending = function(a, b) return a < b end
}

function _M.sort_table_iter(t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0
  local iter = function ()
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end

function _M.reverse_table(arr)
  -- this could be O(n/2)
  local reversed = {}
  for _, i in ipairs(arr) do
    table.insert(reversed, 1, i)
  end
  return reversed
end

function _M.table_contains(arr, val)
  for _, v in pairs(arr) do
    if v == val then
      return true
    end
  end
  return false
end

function _M.is_array(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil and t[tostring(i)] == nil then return false end
  end
  return true
end

-- Add an error message to a key/value table.
-- Can accept a nil argument, and if is nil, will initialize the table.
-- @param `errors`  (Optional) Can be nil. Table to attach the error to. If nil, the table will be created.
-- @param `k`       Key on which to insert the error in the `errors` table.
-- @param `v`       Value of the error
-- @return `errors` The `errors` table with the new error inserted.
function _M.add_error(errors, k, v)
  if not errors then errors = {} end

  if errors and errors[k] and v then
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
