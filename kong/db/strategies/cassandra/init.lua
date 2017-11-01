local cassandra = require "cassandra"


local fmt           = string.format
local rep           = string.rep
local insert        = table.insert
local concat        = table.concat
local setmetatable  = setmetatable
local encode_base64 = ngx.encode_base64
local decode_base64 = ngx.decode_base64
local new_tab
local clear_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function(narr, nrec)
      return {}
    end
  end

  ok, clear_tab = pcall(require, "table.clear")
  if not ok then
    clear_tab = function (tab)
      for k, _ in pairs(tab) do
        tab[k] = nil
      end
    end
  end
end


local APPLIED_COLUMN = "[applied]"


local _constraints = {}


local _M  = {
  CUSTOM_STRATEGIES = {
    services = require("kong.db.strategies.cassandra.services"),
    routes   = require("kong.db.strategies.cassandra.routes"),
  }
}

local _mt = {}
_mt.__index = _mt


local function extract_pk_values(schema, entity)
  local pk_len = #schema.primary_key
  local pk_values = new_tab(0, pk_len)

  for i = 1, pk_len do
    local pk_name = schema.primary_key[i]
    pk_values[pk_name] = entity[pk_name]
  end

  return pk_values
end


local function serialize_arg(field, arg)
  local serialized_arg

  if arg == ngx.null then
    serialized_arg = cassandra.null

  elseif field.uuid then
    serialized_arg = cassandra.uuid(arg)

  elseif field.timestamp then
    serialized_arg = cassandra.timestamp(arg * 1000)

  elseif field.type == "integer" then
    serialized_arg = cassandra.int(arg)

  elseif field.type == "float" then
    serialized_arg = cassandra.float(arg)

  elseif field.type == "boolean" then
    serialized_arg = cassandra.boolean(arg)

  elseif field.type == "string" then
    serialized_arg = cassandra.text(arg)

  elseif field.type == "array" then
    serialized_arg = cassandra.list(arg)

    for i = 1, #arg do
      serialized_arg[i] = serialize_arg(field.elements, arg[i])
    end

  elseif field.type == "set" then
    serialized_arg = cassandra.list(arg)

    for i = 1, #arg do
      serialized_arg[i] = serialize_arg(field.elements, arg[i])
    end

  elseif field.type == "map" then
    serialized_arg = cassandra.map(arg)

    for k, v in pairs(arg) do
      serialized_arg[k] = serialize_arg(field.elements, arg[k])
    end

  else
    error("[cassandra strategy] don't know how to serialize field")
  end

  return serialized_arg
end


local function serialize_foreign_pk(db_columns, args, args_names, foreign_pk)
  for _, db_column in ipairs(db_columns) do
    local to_serialize

    if foreign_pk == ngx.null then
      to_serialize = ngx.null

    else
      to_serialize = foreign_pk[db_column.name]
    end

    insert(args, serialize_arg(db_column.field, to_serialize))

    if args_names then
      insert(args_names, db_column.col_name)
    end
  end
end


-- Check existence of foreign entity.
--
-- Note: this follows an innevitable "read-before-write" pattern in
-- our Cassandra strategy. While unfortunate, this pattern is made
-- necessary for Kong to behave in a database-agnostic fashion between
-- its supported RDBMs and Cassandra. This pattern is judged acceptable
-- given the relatively low number of expected writes (more or less at
-- a human pace), and mitigated by the introduction of different levels
-- of consistency for read vs. write queries, as well as the linearizable
-- consistency of lightweight transactions (IF [NOT] EXISTS).
local function foreign_pk_exists(self, field_name, field, foreign_pk)
  local foreign_schema = field.schema
  local foreign_strategy = _M.new(self.connector, foreign_schema,
                                  self.errors)

  local foreign_row, err_t = foreign_strategy:select(foreign_pk)
  if err_t then
    return nil, err_t
  end

  if not foreign_row then
    return nil, self.errors:foreign_key_violation_invalid_reference(foreign_pk,
                                                                    field_name,
                                                                    foreign_schema.name)
  end

  return true
end


function _M.new(connector, schema, errors)
  local n_fields                = #schema.fields
  local n_pk                    = #schema.primary_key
  local select_bind_args        = new_tab(n_pk, 0)
  local insert_columns          = new_tab(n_fields, 0)
  local insert_bind_args        = rep("?, ", n_fields):sub(1, -3)
  local foreign_keys_db_columns = {}

  local each_pk_field
  local each_non_pk_field

  do
    local non_pk_fields = new_tab(n_fields - n_pk, 0)
    local pk_fields     = new_tab(n_pk, 0)

    for field_name, field in schema:each_field() do
      local is_pk
      for _, pk_field_name in ipairs(schema.primary_key) do
        if field_name == pk_field_name then
          is_pk = true
          break
        end
      end

      insert(is_pk and pk_fields or non_pk_fields, {
        field_name = field_name,
        field      = field,
      })
    end

    local function iter(t, i)
      i = i + 1
      local f = t[i]
      if f then
        return i, f.field_name, f.field
      end
    end

    each_pk_field = function()
      return iter, pk_fields, 0
    end

    each_non_pk_field = function()
      return iter, non_pk_fields, 0
    end
  end

  for _, field_name in each_pk_field() do
    insert(select_bind_args, field_name .. " = ?")
  end

  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local foreign_schema = field.schema
      local foreign_pk     = foreign_schema.primary_key
      local foreign_pk_len = #foreign_pk
      local db_columns     = new_tab(foreign_pk_len, 0)

      for i = 1, foreign_pk_len do
        for foreign_field_name, foreign_field in foreign_schema:each_field() do
          if foreign_field_name == foreign_pk[i] then
            insert(db_columns, {
              col_name = field_name .. "_" .. foreign_pk[i],
              name     = foreign_field_name,
              field    = foreign_field,
            })
          end
        end
      end

      foreign_keys_db_columns[field_name] = db_columns

      for i = 1, #db_columns do
        insert(insert_columns, db_columns[i].col_name)
      end

      -- store in constraints to subsequently retrieve the inverse relation

      _constraints[field.reference] = {
        schema     = schema,
        field_name = field_name,
      }

    else
      insert(insert_columns, field_name)
    end
  end

  insert_columns   = concat(insert_columns, ", ")
  select_bind_args = concat(select_bind_args, " AND ")

  -- build queries

  local insert_query = fmt([[
    INSERT INTO %s(partition, %s) VALUES('%s', %s) IF NOT EXISTS
  ]], schema.name, insert_columns, schema.name, insert_bind_args)

  local select_query = fmt([[
    SELECT %s FROM %s WHERE partition = '%s' AND %s
  ]], insert_columns, schema.name, schema.name, select_bind_args)

  local select_page_query = fmt([[
    SELECT %s FROM %s WHERE partition = '%s'
  ]], insert_columns, schema.name, schema.name)

  local select_with_filter = fmt([[
    SELECT %s FROM %s WHERE partition = '%s' AND %s
  ]], insert_columns, schema.name, schema.name, "%s")

  local update_query = fmt([[
    UPDATE %s SET %s WHERE partition = '%s' AND %s IF EXISTS
  ]], schema.name, "%s", schema.name, select_bind_args)

  local delete_query = fmt([[
    DELETE FROM %s WHERE partition = '%s' AND %s
  ]], schema.name, schema.name, select_bind_args)

  local self = {
    connector               = connector, -- instance of kong.db.strategies.cassandra.init
    schema                  = schema,
    errors                  = errors,
    each_pk_field           = each_pk_field,
    each_non_pk_field       = each_non_pk_field,
    foreign_keys_db_columns = foreign_keys_db_columns,

    queries = {
      insert             = insert_query,
      select             = select_query,
      select_page        = select_page_query,
      select_with_filter = select_with_filter,
      update             = update_query,
      delete             = delete_query,
    }
  }

  return setmetatable(self, _mt)
end


function _mt:insert(entity)
  local schema = self.schema
  local cql = self.queries.insert
  local args = new_tab(#schema.fields, 0)

  -- serialize VALUES clause args

  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local foreign_pk = entity[field_name]

      if foreign_pk ~= ngx.null then
        -- if given, check if this foreign entity exists
        local exists, err_t = foreign_pk_exists(self, field_name, field, foreign_pk)
        if not exists then
          return nil, err_t
        end
      end

      local db_columns = self.foreign_keys_db_columns[field_name]
      serialize_foreign_pk(db_columns, args, nil, foreign_pk)

    else
      insert(args, serialize_arg(field, entity[field_name]))
    end
  end

  -- execute query

  local res, err = self.connector:query(cql, args, nil, "write")
  if not res then
    return nil, self.errors:database_error("could not execute insertion query: "
                                           .. err)
  end

  -- check for linearizable consistency (Paxos)

  if res[APPLIED_COLUMN] == false then
    -- lightweight transaction (IF NOT EXISTS) failed,
    -- retrieve PK values for the PK violation error
    local pk_values = extract_pk_values(schema, entity)

    return nil, self.errors:primary_key_violation(pk_values)
  end

  -- return foreign key as if they were fetched from :select()
  -- this means foreign relationship tables should only contain
  -- the primary key of the foreign entity

  clear_tab(res)

  for field_name, field in schema:each_field() do
    local value = entity[field_name]

    if field.type == "foreign" then
      if value ~= ngx.null and value ~= nil then
        value = extract_pk_values(field.schema, value)

      else
        value = ngx.null
      end
    end

    res[field_name] = value
  end

  return res
end


local function deserialize_row(self, row)
  if not row then
    error("row must be a table", 2)
  end

  -- deserialize rows
  -- replace `nil` fields with `ngx.null`
  -- replace `foreign_key` with `foreign = { key = "" }`
  -- give seconds precisions to timestamps instead of ms

  for field_name, field in self.schema:each_field() do
    if field.type == "foreign" then
      local db_columns = self.foreign_keys_db_columns[field_name]

      local has_fk
      row[field_name] = new_tab(0, #db_columns)

      for i = 1, #db_columns do
        local col_name = db_columns[i].col_name

        if row[col_name] ~= nil then
          row[field_name][db_columns[i].name] = row[col_name]
          row[col_name] = nil

          has_fk = true
        end
      end

      if not has_fk then
        row[field_name] = nil
      end

    elseif field.timestamp then
      row[field_name] = row[field_name] / 1000
    end

    if row[field_name] == nil then
      row[field_name] = ngx.null
    end
  end

  return row
end


local function select(self, cql, args)
  local rows, err = self.connector:query(cql, args, nil, "read")
  if not rows then
    return nil, self.errors:database_error("could not execute selection query: "
                                           .. err)
  end

  -- lua-cassandra returns `nil` values for Cassandra's `NULL`. We need to
  -- populate `ngx.null` ourselves

  local row = rows[1]
  if not row then
    return nil
  end

  return deserialize_row(self, row)
end

function _mt:select(primary_key)
  local schema = self.schema
  local cql = self.queries.select
  local args = new_tab(#schema.primary_key, 0)

  -- serialize WHERE clause args

  for i, field_name, field in self.each_pk_field() do
    args[i] = serialize_arg(field, primary_key[field_name])
  end

  -- execute query

  return select(self, cql, args)
end


do
  local opts = new_tab(0, 2)


  function _mt:page(size, offset)
    if offset then
      local offset_decoded = decode_base64(offset)
      if not offset_decoded then
        return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
      end

      offset = offset_decoded
    end

    local cql = self.queries.select_page

    opts.page_size = size
    opts.paging_state = offset

    local rows, err = self.connector:query(cql, nil, opts, "read")
    if not rows then
      return nil, self.errors:database_error("could not execute page query: "
                                             .. err)
    end

    for i = 1, #rows do
      rows[i] = deserialize_row(self, rows[i])
    end

    local next_offset
    if rows.meta and rows.meta.paging_state then
      next_offset = encode_base64(rows.meta.paging_state)
    end

    rows.meta = nil
    rows.type = nil

    return rows, nil, next_offset
  end
end


do
  local function iter(self)
    if not self.rows then
      local size = self.size
      local offset = self.offset
      local strategy = self.strategy

      local rows, err_t, next_offset = strategy:page(size, offset)
      if not rows then
        return nil, err_t
      end

      self.rows = rows
      self.rows_idx = 0
      self.offset = next_offset
      self.page = self.page + 1
    end

    local rows_idx = self.rows_idx
    rows_idx = rows_idx + 1

    local row = self.rows[rows_idx]
    if row then
      self.rows_idx = rows_idx
      return row, nil, self.page
    end

    -- end of page

    if not self.offset then
      -- end of iteration
      return nil
    end

    self.rows = nil

    -- fetch next page
    return iter(self)
  end


  local iter_mt = { __call = iter }


  function _mt:each(size)
    local iter_ctx = {
      page         = 0,
      rows         = nil,
      rows_idx     = nil,
      offset       = nil,
      size         = size,
      strategy     = self,
    }

    return setmetatable(iter_ctx, iter_mt)
  end
end


function _mt:update(primary_key, entity)
  local schema = self.schema
  local cql = self.queries.update
  local args = new_tab(#schema.fields, 0)
  local args_names = new_tab(#schema.fields, 0)

  -- serialize SET clause args

  for _, field_name, field in self.each_non_pk_field() do
    if entity[field_name] ~= nil then
      if field.type == "foreign" then
        local foreign_pk = entity[field_name]

        if foreign_pk ~= ngx.null then
          -- if given, check if this foreign entity exists
          local exists, err_t = foreign_pk_exists(self, field_name, field, foreign_pk)
          if not exists then
            return nil, err_t
          end
        end

        local db_columns = self.foreign_keys_db_columns[field_name]
        serialize_foreign_pk(db_columns, args, args_names, foreign_pk)

      else
        insert(args, serialize_arg(field, entity[field_name]))
        insert(args_names, field_name)
      end
    end
  end

  -- serialize WHERE clause args

  for i, field_name, field in self.each_pk_field() do
    insert(args, serialize_arg(field, primary_key[field_name]))
  end

  -- inject SET clause bindings

  local n_args = #args_names
  local update_columns_binds = new_tab(n_args, 0)

  for i = 1, n_args do
    update_columns_binds[i] = args_names[i] .. " = ?"
  end

  cql = fmt(cql, concat(update_columns_binds, ", "))

  -- execute query

  local res, err = self.connector:query(cql, args, nil, "write")
  if not res then
    return nil, self.errors:database_error("could not execute update query: "
                                           .. err)
  end

  if res[1][APPLIED_COLUMN] == false then
    return nil, self.errors:not_found(primary_key)
  end

  -- SELECT after write

  local row, err_t = self:select(primary_key)
  if err_t then
    return nil, err_t
  end

  if not row then
    return nil, self.errors:not_found(primary_key)
  end

  return row
end

do
  local function select_by_foreign_key(self, foreign_schema,
                                       foreign_field_name, foreign_key)
    local n_fields = #foreign_schema.fields
    local strategy = _M.new(self.connector, foreign_schema, self.errors)
    local cql = strategy.queries.select_with_filter
    local args = new_tab(n_fields, 0)
    local args_names = new_tab(n_fields, 0)

    local db_columns = strategy.foreign_keys_db_columns[foreign_field_name]
    serialize_foreign_pk(db_columns, args, args_names, foreign_key)

    local n_args = #args_names
    local where_clause_binds = new_tab(n_args, 0)
    for i = 1, n_args do
      where_clause_binds[i] = args_names[i] .. " = ?"
    end

    cql = fmt(cql, concat(where_clause_binds, " AND "))

    return select(strategy, cql, args)
  end


  function _mt:delete(primary_key)
    local schema = self.schema
    local cql = self.queries.delete
    local args = new_tab(#schema.primary_key, 0)

    local constraint = _constraints[schema.name]
    if constraint then
      -- foreign keys could be pointing to this entity
      -- this mimics the "ON DELETE" constraint of supported
      -- RDBMs (e.g. PostgreSQL)
      --
      -- The possible behaviors on such a constraint are:
      --  * RESTRICT (default)
      --  * CASCADE  (NYI)
      --  * SET NULL (NYI)

      local row, err_t = select_by_foreign_key(self,
                                               constraint.schema,
                                               constraint.field_name,
                                               primary_key)
      if err_t then
        return nil, err_t
      end

      if row then
        -- a row is referring to this entity, we cannot delete it.
        -- deleting the parent entity would violate the foreign key
        -- constraint
        return nil, self.errors:foreign_key_violation_restricted(schema.name,
                                                                 constraint.schema.name)
      end
    end

    -- serialize WHERE clause args

    for i, field_name, field in self.each_pk_field() do
      args[i] = serialize_arg(field, primary_key[field_name])
    end

    -- execute query

    local res, err = self.connector:query(cql, args, nil, "write")
    if not res then
      return nil, self.errors:database_error("could not execute deletion query: "
                                             .. err)
    end

    return true
  end
end


return _M
