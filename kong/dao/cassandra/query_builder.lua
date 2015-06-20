local _M = {}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function select_fragment(column_family, select_columns)
  if select_columns then
    assert(type(select_columns) == "table", "select_columns must be a table")
    select_columns = table.concat(select_columns, ", ")
  else
    select_columns = "*"
  end

  return string.format("SELECT %s FROM %s", select_columns, column_family)
end

local function insert_fragment(column_family, insert_values)
  local values_placeholders, columns = {}, {}
  for column, value in pairs(insert_values) do
    table.insert(values_placeholders, "?")
    table.insert(columns, column)
  end

  local columns_names_str = table.concat(columns, ", ")
  values_placeholders = table.concat(values_placeholders, ", ")

  return string.format("INSERT INTO %s(%s) VALUES(%s)", column_family, columns_names_str, values_placeholders), columns
end

local function update_fragment(column_family, update_values)
  local placeholders, update_columns = {}, {}
  for column in pairs(update_values) do
    table.insert(update_columns, column)
    table.insert(placeholders, string.format("%s = ?", column))
  end

  placeholders = table.concat(placeholders, ", ")

  return string.format("UPDATE %s SET %s", column_family, placeholders), update_columns
end

local function delete_fragment(column_family)
  return string.format("DELETE FROM %s", column_family)
end

local function where_fragment(where_t, column_family_details, no_filtering_check)
  if not where_t then where_t = {} end
  if not column_family_details then column_family_details = {} end

  assert(type(where_t) == "table", "where_t must be a table")
  if next(where_t) == nil then
    if not no_filtering_check then
      return ""
    else
      error("where_t must contain keys")
    end
  end

  if column_family_details.primary_key then
    assert(type(column_family_details.primary_key) == "table", "primary_key must be a table")
  else
    column_family_details.primary_key = {}
  end

  if column_family_details.clustering_key then
    assert(type(column_family_details.clustering_key) == "table", "clustering_key must be a table")
  else
    column_family_details.clustering_key= {}
  end

  if column_family_details.indexes then
    assert(type(column_family_details.indexes) == "table", "indexes must be a table")
  else
    column_family_details.indexes = {}
  end

  local where_parts, columns = {}, {}
  local needs_filtering = false
  local filtering = ""
  local n_indexed_cols = 0

  for column in pairs(where_t) do
    table.insert(where_parts, string.format("%s = ?", column))
    table.insert(columns, column)

    if not no_filtering_check and not needs_filtering then -- as soon as we need it, it's not revertible
      -- check if this field belongs to the primary_key
      local primary_contains = false
      for _, key in ipairs(column_family_details.primary_key) do
        if column == key then
          primary_contains = true
          break
        end
      end
      for _, key in ipairs(column_family_details.clustering_key) do
        if column == key then
          primary_contains = true
          break
        end
      end
      -- check the number of indexed fields being queried. If more than 1, we need filtering
      if column_family_details.indexes[column] then
        n_indexed_cols = n_indexed_cols + 1
      end
      -- if the column is not part of the primary key, nor indexed, or if we have more
      -- than one indexed column being queried, we need filtering.
      if (not primary_contains and not column_family_details.indexes[column]) or n_indexed_cols > 1 then
        needs_filtering = true
      end
    end
  end

  if needs_filtering then
    filtering = " ALLOW FILTERING"
  else
    needs_filtering = false
  end

  where_parts = table.concat(where_parts, " AND ")

  return string.format("WHERE %s%s", where_parts, filtering), columns, needs_filtering
end

function _M.select(column_family, where_t, column_family_details, select_columns)
  assert(type(column_family) == "string", "column_family must be a string")

  local select_str = select_fragment(column_family, select_columns)
  local where_str, columns, needed_filtering = where_fragment(where_t, column_family_details)

  return trim(string.format("%s %s", select_str, where_str)), columns, needed_filtering
end

function _M.insert(column_family, insert_values)
  assert(type(column_family) == "string", "column_family must be a string")
  assert(type(insert_values) == "table", "insert_values must be a table")
  assert(next(insert_values) ~= nil, "insert_values cannot be empty")

  return insert_fragment(column_family, insert_values)
end

function _M.update(column_family, update_values, where_t)
  assert(type(column_family) == "string", "column_family must be a string")
  assert(type(update_values) == "table", "update_values must be a table")
  assert(next(update_values) ~= nil, "update_values cannot be empty")

  local update_str, update_columns = update_fragment(column_family, update_values)
  local where_str, where_columns = where_fragment(where_t, nil, true)

  -- concat columns from SET and WHERE parts of the query
  local columns = {}
  if update_columns then
    columns = update_columns
  end
  if where_columns then
    for _, v in ipairs(where_columns) do
      table.insert(columns, v)
    end
  end

  return trim(string.format("%s %s", update_str, where_str)), columns
end

function _M.delete(column_family, where_t)
  assert(type(column_family) == "string", "column_family must be a string")

  local delete_str = delete_fragment(column_family)
  local where_str, where_columns = where_fragment(where_t, nil, true)

  return trim(string.format("%s %s", delete_str, where_str)), where_columns
end

function _M.truncate(column_family)
  assert(type(column_family) == "string", "column_family must be a string")

  return "TRUNCATE "..column_family
end

return _M
