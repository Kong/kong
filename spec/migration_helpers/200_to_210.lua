-- Helper module for testing 200_to_210 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned helper module.

local fmt = string.format
local cassandra = require "cassandra"
local assert = require "luassert"

local PG_HAS_COLUMN_SQL = [[
  SELECT *
  FROM information_schema.columns
  WHERE table_schema = 'public'
  AND table_name     = '%s'
  AND column_name    = '%s';
]]

local PG_HAS_CONSTRAINT_SQL = [[
  SELECT *
  FROM pg_catalog.pg_constraint
  WHERE conname = '%s';
]]

local PG_HAS_INDEX_SQL = [[
  SELECT *
  FROM pg_indexes
  WHERE indexname = '%s';
]]

local PG_HAS_TABLE_SQL = [[
  SELECT *
  FROM pg_catalog.pg_tables
  WHERE schemaname = 'public'
  AND tablename = '%s';
]]

local _M = {}

function _M.assert_pg_has_column(cn, table_name, column_name, data_type)
  local res = assert(cn:query(fmt(PG_HAS_COLUMN_SQL, table_name, column_name)))

  assert.equals(1, #res)
  assert.equals(column_name, res[1].column_name)
  assert.equals(string.lower(data_type), string.lower(res[1].data_type))
end


function _M.assert_not_pg_has_column(cn, table_name, column_name, data_type)
  local res = assert(cn:query(fmt(PG_HAS_COLUMN_SQL, table_name, column_name)))
  assert.same({}, res)
end


function _M.assert_pg_has_constraint(cn, constraint_name)
  local res = assert(cn:query(fmt(PG_HAS_CONSTRAINT_SQL, constraint_name)))

  assert.equals(1, #res)
  assert.equals(constraint_name, res[1].conname)
end


function _M.assert_not_pg_has_constraint(cn, constraint_name)
  local res = assert(cn:query(fmt(PG_HAS_CONSTRAINT_SQL, constraint_name)))
  assert.same({}, res)
end


function _M.assert_pg_has_index(cn, index_name)
  local res = assert(cn:query(fmt(PG_HAS_INDEX_SQL, index_name)))

  assert.equals(1, #res)
  assert.equals(index_name, res[1].indexname)
end


function _M.assert_not_pg_has_index(cn, index_name)
  local res = assert(cn:query(fmt(PG_HAS_INDEX_SQL, index_name)))
  assert.same({}, res)
end


function _M.assert_pg_has_fkey(cn, table_name, column_name)
  _M.assert_pg_has_column(cn, table_name, column_name, "uuid")
  _M.assert_pg_has_constraint(cn, table_name .. "_" .. column_name .. "_fkey")
end


function _M.assert_not_pg_has_fkey(cn, table_name, column_name)
  _M.assert_not_pg_has_column(cn, table_name, column_name, "uuid")
  _M.assert_not_pg_has_constraint(cn, table_name .. "_" .. column_name .. "_fkey")
end


function _M.assert_pg_has_table(cn, table_name)
  local res = assert(cn:query(fmt(PG_HAS_TABLE_SQL, table_name)))

  assert.equals(1, #res)
  assert.equals(table_name, res[1].tablename)
end


function _M.assert_not_pg_has_table(cn, table_name)
  local res = assert(cn:query(fmt(PG_HAS_TABLE_SQL, table_name)))
  assert.same({}, res)
end


function _M.pg_insert(cn, table_name, tbl)
  local columns, values = {},{}
  for k,_ in pairs(tbl) do
    columns[#columns + 1] = k
  end
  table.sort(columns)
  for i, c in ipairs(columns) do
    local v = tbl[c]
    v = type(v) == "string" and "'" .. v .. "'" or v
    values[i] = tostring(v)
  end
  local sql = fmt([[
    INSERT INTO %s (%s) VALUES (%s)
  ]],
    table_name,
    table.concat(columns, ","),
    table.concat(values, ",")
  )

  local res = assert(cn:query(sql))

  assert.same({ affected_rows = 1 }, res)

  return assert(cn:query(fmt("SELECT * FROM %s WHERE id='%s'", table_name, tbl.id)))[1]
end

---------------------

local C_TABLE_HAS_COLUMN_CQL = [[
  SELECT * FROM system_schema.columns
  WHERE keyspace_name = '%s'
  AND table_name = '%s'
  AND column_name = '%s'
  ALLOW FILTERING;
]]

local C_HAS_INDEX_CQL = [[
  SELECT * FROM system_schema.indexes
  WHERE keyspace_name='%s'
  AND table_name='%s'
  AND index_name='%s'
]]

local C_HAS_TABLE_CQL = [[
  SELECT * FROM system_schema.tables
  WHERE keyspace_name='%s'
  AND table_name = '%s';
]]


function _M.assert_not_c_has_column(cn, table_name, column_name)
  local res = assert(cn:query(fmt(C_TABLE_HAS_COLUMN_CQL, cn.keyspace, table_name, column_name)))
  assert.equals(0, #res)
  assert.same({ has_more_pages = false }, res.meta)
end


function _M.assert_c_has_column(cn, table_name, column_name, column_type)
  local res = assert(cn:query(fmt(C_TABLE_HAS_COLUMN_CQL, cn.keyspace, table_name, column_name)))
  assert.equals(1, #res)
  assert.equals(column_name, res[1].column_name)
  assert.equals(column_type, res[1].type)
  assert.same({ has_more_pages = false }, res.meta)
  return res[1]
end


function _M.assert_not_c_has_index(cn, table_name, index_name)
  local res = assert(cn:query(fmt(C_HAS_INDEX_CQL, cn.keyspace, table_name, index_name)))
  assert.equals(0, #res)
  assert.same({ has_more_pages = false }, res.meta)
end


function _M.assert_c_has_index(cn, table_name, index_name)
  local cql = fmt(C_HAS_INDEX_CQL, cn.keyspace, table_name, index_name)
  local res = assert(cn:query(cql))
  assert.equals(1, #res)
  assert.equals(index_name, res[1].index_name)
  assert.same({ has_more_pages = false }, res.meta)
  return res[1]
end


function _M.assert_not_c_has_fkey(cn, table_name, column_name)
  _M.assert_not_c_has_column(cn, table_name, column_name, "uuid")
  _M.assert_not_c_has_index(cn, table_name, table_name .. "_" .. column_name .. "_idx")
end


function _M.assert_c_has_fkey(cn, table_name, column_name)
  local res = _M.assert_c_has_column(cn, table_name, column_name, "uuid")
  _M.assert_c_has_index(cn, table_name, table_name .. "_" .. column_name .. "_idx")
  return res
end


function _M.assert_not_c_has_table(cn, table_name)
  local res = assert(cn:query(fmt(C_HAS_TABLE_CQL, cn.keyspace, table_name)))
  assert.equals(0, #res)
  assert.same({ has_more_pages = false }, res.meta)
end


function _M.assert_c_has_table(cn, table_name)
  local res = assert(cn:query(fmt(C_HAS_TABLE_CQL, cn.keyspace, table_name)))
  assert.equals(1, #res)
  assert.equals(table_name, res[1].table_name)
  assert.same({ has_more_pages = false }, res.meta)
  return res[1]
end


function _M.c_insert(cn, table_name, tbl)
  local columns, bindings, values = {},{},{}
  for k,_ in pairs(tbl) do
    columns[#columns + 1] = k
  end
  table.sort(columns)
  for i, c in ipairs(columns) do
    bindings[#bindings + 1] = "?"
    local v = tbl[c]
    if c ~= "custom_id" and c:sub(-2) == "id" then
      v = cassandra.uuid(v)
    end
    values[i] = v
  end

  local cql = fmt([[
    INSERT INTO %s(%s) VALUES(%s)
  ]],
    table_name,
    table.concat(columns, ", "),
    table.concat(bindings, ", ")
  )
  local res = assert(cn:query(cql, values))

  assert.same({ type = "VOID" }, res)

  if tbl.partition then
    return assert(cn:query(fmt("SELECT * FROM %s WHERE partition=? AND id=?", table_name),
                           { tbl.partition, cassandra.uuid(tbl.id) }))[1]
  end

  return assert(cn:query(fmt("SELECT * FROM %s WHERE id=?", table_name),
                         { cassandra.uuid(tbl.id) }))[1]
end

return _M
