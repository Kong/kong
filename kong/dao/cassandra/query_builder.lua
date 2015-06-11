local _M = {}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function select_fragment(column_family, select_columns)
  assert(type(column_family) == "string", "column_family must be a string")

  if select_columns then
    assert(type(select_columns) == "table", "select_columns must be a table")
    select_columns = table.concat(select_columns, ", ")
  else
    select_columns = "*"
  end

  return string.format("SELECT %s FROM %s", select_columns, column_family)
end

local function insert_fragment(column_family, insert_values)
  assert(type(column_family) == "string", "column_family must be a string")
  assert(type(insert_values) == "table", "insert_values must be a table")

  local columns_names = {}
  local values_placeholders = {}
  for column, value in pairs(insert_values) do
    table.insert(values_placeholders, "?")
    table.insert(columns_names, column)
  end

  columns_names = table.concat(columns_names, ", ")
  values_placeholders = table.concat(values_placeholders, ", ")

  return string.format("INSERT INTO %s(%s) VALUES(%s)", column_family, columns_names, values_placeholders)
end

local function update_fragment(column_family, update_values)
  assert(type(column_family) == "string", "column_family must be a string")
  assert(type(update_values) == "table", "update_values must be a table")

  local placeholders = {}
  for column in pairs(update_values) do
    table.insert(placeholders, string.format("%s = ?", column))
  end

  placeholders = table.concat(placeholders, ", ")

  return string.format("UPDATE %s SET %s", column_family, placeholders)
end

local function delete_fragment(column_family)
  assert(type(column_family) == "string", "column_family must be a string")

  return string.format("DELETE FROM %s", column_family)
end

local function where_fragment(where_values)
  if not where_values then return "" end
  local where_parts = {}

  for k in pairs(where_values) do
    table.insert(where_parts, string.format("%s = ?", k))
  end

  where_parts = table.concat(where_parts, " AND ")

  return string.format("WHERE %s", where_parts)
end

--
--
--

function _M.select(column_family, where_values, select_columns)
  local select_str = select_fragment(column_family, select_columns)
  local where_str = where_fragment(where_values)

  return trim(string.format("%s %s", select_str, where_str))
end

function _M.insert(column_family, insert_values)
  return insert_fragment(column_family, insert_values)
end

function _M.update(column_family, update_values, where_values)
  local update_str = update_fragment(column_family, update_values)
  local where_str = where_fragment(where_values)

  return trim(string.format("%s %s", update_str, where_str))
end

function _M.delete(column_family, where_values)
  local delete_str = delete_fragment(column_family)
  local where_str = where_fragment(where_values)

  return trim(string.format("%s %s", delete_str, where_str))
end

return _M
