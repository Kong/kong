local iteration = require "kong.db.iteration"
local cassandra = require "cassandra"
local cjson = require "cjson"


local fmt           = string.format
local rep           = string.rep
local null          = ngx.null
local type          = type
local error         = error
local pairs         = pairs
local ipairs        = ipairs
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


local cache_key_field = { type = "string" }


local _M  = {}

local _mt = {}
_mt.__index = _mt


local function is_partitioned(self)
  local cql

  -- Assume a release version number of 3 & greater will use the same schema.
  if self.connector.major_version >= 3 then
    cql = fmt([[
      SELECT * FROM system_schema.columns
      WHERE keyspace_name = '%s'
      AND table_name = '%s'
      AND column_name = 'partition';
    ]], self.connector.keyspace, self.schema.name)

  else
    cql = fmt([[
      SELECT * FROM system.schema_columns
      WHERE keyspace_name = '%s'
      AND columnfamily_name = '%s'
      AND column_name = 'partition';
    ]], self.connector.keyspace, self.schema.name)
  end

  local rows, err = self.connector:query(cql, {}, nil, "read")
  if err then
    return nil, err
  end

  -- Assume a release version number of 3 & greater will use the same schema.
  if self.connector.major_version >= 3 then
    return rows[1] and rows[1].kind == "partition_key"
  end

  return not not rows[1]
end


local function build_queries(self)
  local schema   = self.schema
  local n_fields = #schema.fields
  local n_pk     = #schema.primary_key
  local composite_cache_key = schema.cache_key and #schema.cache_key > 1

  local select_columns = new_tab(n_fields, 0)
  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local db_columns = self.foreign_keys_db_columns[field_name]
      for i = 1, #db_columns do
        insert(select_columns, db_columns[i].col_name)
      end
    else
      insert(select_columns, field_name)
    end
  end
  select_columns = concat(select_columns, ", ")
  local insert_columns = select_columns

  local insert_bind_args = rep("?, ", n_fields):sub(1, -3)

  if composite_cache_key then
    insert_columns = select_columns .. ", cache_key"
    insert_bind_args = insert_bind_args .. ", ?"
  end

  local select_bind_args = new_tab(n_pk, 0)
  for _, field_name in self.each_pk_field() do
    if schema.fields[field_name].type == "foreign"  then
      field_name = field_name .. "_" .. schema.fields[field_name].schema.primary_key[1]
    end

    insert(select_bind_args, field_name .. " = ?")
  end
  select_bind_args = concat(select_bind_args, " AND ")

  local partitioned, err = is_partitioned(self)
  if err then
    return nil, err
  end

  if schema.ttl == true then
    select_columns = select_columns .. fmt(", TTL(%s) as ttl", self.ttl_field())
  end

  if partitioned then
    return {
      insert = fmt([[
        INSERT INTO %s (partition, %s) VALUES ('%s', %s) IF NOT EXISTS
      ]], schema.name, insert_columns, schema.name, insert_bind_args),

      insert_ttl = fmt([[
        INSERT INTO %s (partition, %s) VALUES ('%s', %s) IF NOT EXISTS USING TTL %s
      ]], schema.name, insert_columns, schema.name, insert_bind_args, "%u"),

      insert_no_transaction = fmt([[
        INSERT INTO %s (partition, %s) VALUES ('%s', %s)
      ]], schema.name, insert_columns, schema.name, insert_bind_args),

      insert_no_transaction_ttl = fmt([[
        INSERT INTO %s (partition, %s) VALUES ('%s', %s) USING TTL %s
      ]], schema.name, insert_columns, schema.name, insert_bind_args, "%u"),

      select = fmt([[
        SELECT %s FROM %s WHERE partition = '%s' AND %s
      ]], select_columns, schema.name, schema.name, select_bind_args),

      select_page = fmt([[
        SELECT %s FROM %s WHERE partition = '%s'
      ]], select_columns, schema.name, schema.name),

      select_with_filter = fmt([[
        SELECT %s FROM %s WHERE partition = '%s' AND %s
      ]], select_columns, schema.name, schema.name, "%s"),

      select_tags_cond_and_first_tag = fmt([[
        SELECT entity_id FROM tags WHERE entity_name = '%s' AND tag = ?
      ]], schema.name),

      select_tags_cond_and_next_tags = fmt([[
        SELECT entity_id FROM tags WHERE entity_name = '%s' AND tag = ? AND entity_id IN ?
      ]], schema.name),

      select_tags_cond_or = fmt([[
        SELECT tag, entity_id, other_tags FROM tags WHERE entity_name = '%s' AND tag IN ?
      ]], schema.name),

      update = fmt([[
        UPDATE %s SET %s WHERE partition = '%s' AND %s IF EXISTS
      ]], schema.name, "%s", schema.name, select_bind_args),

      update_ttl = fmt([[
        UPDATE %s USING TTL %s SET %s WHERE partition = '%s' AND %s IF EXISTS
      ]], schema.name, "%u", "%s", schema.name, select_bind_args),

      upsert = fmt([[
        UPDATE %s SET %s WHERE partition = '%s' AND %s
      ]], schema.name, "%s", schema.name, select_bind_args),

      upsert_ttl = fmt([[
        UPDATE %s USING TTL %s SET %s WHERE partition = '%s' AND %s
      ]], schema.name, "%u", "%s", schema.name, select_bind_args),

      delete = fmt([[
        DELETE FROM %s WHERE partition = '%s' AND %s
      ]], schema.name, schema.name, select_bind_args),
    }
  end

  return {
    insert = fmt([[
      INSERT INTO %s (%s) VALUES (%s) IF NOT EXISTS
    ]], schema.name, insert_columns, insert_bind_args),

    insert_ttl = fmt([[
      INSERT INTO %s (%s) VALUES (%s) IF NOT EXISTS USING TTL %s
    ]], schema.name, insert_columns, insert_bind_args, "%u"),

    insert_no_transaction = fmt([[
      INSERT INTO %s (%s) VALUES (%s)
    ]], schema.name, insert_columns, insert_bind_args),

    insert_no_transaction_ttl = fmt([[
      INSERT INTO %s ( %s) VALUES (%s) USING TTL %s
    ]], schema.name, insert_columns, insert_bind_args, "%u"),

    -- might raise a "you must enable ALLOW FILTERING" error
    select = fmt([[
      SELECT %s FROM %s WHERE %s
    ]], select_columns, schema.name, select_bind_args),

    -- might raise a "you must enable ALLOW FILTERING" error
    select_page = fmt([[
      SELECT %s FROM %s
    ]], select_columns, schema.name),

    -- might raise a "you must enable ALLOW FILTERING" error
    select_with_filter = fmt([[
      SELECT %s FROM %s WHERE %s
    ]], select_columns, schema.name, "%s"),

    select_tags_cond_and_first_tag = fmt([[
      SELECT entity_id FROM tags WHERE entity_name = '%s' AND tag = ?
    ]], schema.name),

    select_tags_cond_and_next_tags = fmt([[
      SELECT entity_id FROM tags WHERE entity_name = '%s' AND tag = ? AND entity_id IN ?
    ]], schema.name),

    select_tags_cond_or = fmt([[
      SELECT tag, entity_id, other_tags FROM tags WHERE entity_name = '%s' AND tag IN ?
    ]], schema.name),

    update = fmt([[
      UPDATE %s SET %s WHERE %s IF EXISTS
    ]], schema.name, "%s", select_bind_args),

    update_ttl = fmt([[
      UPDATE %s USING TTL %s SET %s WHERE %s IF EXISTS
    ]], schema.name, "%u", "%s", select_bind_args),

    upsert = fmt([[
      UPDATE %s SET %s WHERE %s
    ]], schema.name, "%s", select_bind_args),

    upsert_ttl = fmt([[
      UPDATE %s USING TTL %s SET %s WHERE %s
    ]], schema.name, "%u", "%s", select_bind_args),

    delete = fmt([[
      DELETE FROM %s WHERE %s
    ]], schema.name, select_bind_args),
  }
end


local function get_query(self, query_name)
  if not self.queries then
    local err
    self.queries, err = build_queries(self)
    if err then
      return nil, err
    end
  end

  return self.queries[query_name]
end


local function serialize_arg(field, arg)
  local serialized_arg

  if arg == null then
    serialized_arg = cassandra.null

  elseif field.uuid then
    serialized_arg = cassandra.uuid(arg)

  elseif field.timestamp then
    serialized_arg = cassandra.timestamp(arg * 1000)

  elseif field.type == "integer" then
    serialized_arg = cassandra.int(arg)

  elseif field.type == "number" then
    serialized_arg = cassandra.float(arg)

  elseif field.type == "boolean" then
    serialized_arg = cassandra.boolean(arg)

  elseif field.type == "string" then
    serialized_arg = cassandra.text(arg)

  elseif field.type == "array" then
    local t = {}

    for i = 1, #arg do
      t[i] = serialize_arg(field.elements, arg[i])
    end

    serialized_arg = cassandra.list(t)

  elseif field.type == "set" then
    local t = {}

    for i = 1, #arg do
      t[i] = serialize_arg(field.elements, arg[i])
    end

    serialized_arg = cassandra.set(t)

  elseif field.type == "map" then
    local t = {}

    for k, v in pairs(arg) do
      t[k] = serialize_arg(field.values, arg[k])
    end

    serialized_arg = cassandra.map(t)

  elseif field.type == "record" then
    serialized_arg = cassandra.text(cjson.encode(arg))

  elseif field.type == "foreign" then
    local fk_pk = field.schema.primary_key[1]
    local fk_field = field.schema.fields[fk_pk]
    serialized_arg = serialize_arg(fk_field, arg[fk_pk])

  else
    error("[cassandra strategy] don't know how to serialize field")
  end

  return serialized_arg
end


local function serialize_foreign_pk(db_columns, args, args_names, foreign_pk)
  for _, db_column in ipairs(db_columns) do
    local to_serialize

    if foreign_pk == null then
      to_serialize = null

    else
      to_serialize = foreign_pk[db_column.foreign_field_name]
    end

    insert(args, serialize_arg(db_column.foreign_field, to_serialize))

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

local function set_difference(old_set, new_set)
  local new_set_hash = new_tab(0, #new_set)
  for _, elem in ipairs(new_set) do
    new_set_hash[elem] = true
  end

  local old_set_hash = new_tab(0, #old_set)
  for _, elem in ipairs(old_set) do
    old_set_hash[elem] = true
  end

  local elem_to_add = {}
  local elem_to_delete = {}
  local elem_not_changed = {}

  for _, elem in ipairs(new_set) do
    if not old_set_hash[elem] then
      insert(elem_to_add, elem)
    end
  end

  for _, elem in ipairs(old_set) do
    if not new_set_hash[elem] then
      insert(elem_to_delete, elem)
    else
      insert(elem_not_changed, elem)
    end
  end

  return elem_to_add, elem_to_delete, elem_not_changed
end

-- Calculate the difference of current tags and updated tags of an entity
-- return the cql to execute, and error if any
--
-- Note: this follows an innevitable "read-before-write" pattern in
-- our Cassandra strategy. While unfortunate, this pattern is made
-- necessary for Kong to behave in a database-agnostic fashion between
-- its supported RDBMs and Cassandra. This pattern is judged acceptable
-- given the relatively low number of expected writes (more or less at
-- a human pace), and mitigated by the introduction of different levels
-- of consistency for read vs. write queries, as well as the linearizable
-- consistency of lightweight transactions (IF [NOT] EXISTS).
local function build_tags_cql(self, primary_key, schema, new_tags, ttl, read_before_write)
  local tags_to_add, tags_to_delete, tags_not_changed

  new_tags = (not new_tags or new_tags == null) and {} or new_tags

  if read_before_write then
    local strategy = _M.new(self.connector, schema,
                            self.errors)
    local row, err_t = strategy:select(primary_key)
    if err_t then
      return nil, err_t
    end

    if row and row['tags'] and row['tags'] ~= null then
      tags_to_add, tags_to_delete, tags_not_changed = set_difference(row['tags'], new_tags)
    else
      tags_to_add = new_tags
      tags_to_delete = {}
      tags_not_changed = {}
    end
  else
    tags_to_add = new_tags
    tags_to_delete = {}
    tags_not_changed = {}
  end

  if #tags_to_add == 0 and #tags_to_delete == 0 then
    return nil, nil
  end
  -- Note: here we assume tags column only exists
  -- with those entities use id as their primary key
  local entity_id = primary_key['id']
  local cqls = {}
  local update_cql = "UPDATE tags SET other_tags=? WHERE tag=? AND entity_name=? AND entity_id=?"
  if ttl then
    update_cql = update_cql .. fmt(" USING TTL %u", ttl)
  end
  for _, tag in ipairs(tags_not_changed) do
    insert(cqls,
      {
        update_cql,
        { cassandra.set(new_tags), cassandra.text(tag), cassandra.text(schema.name), cassandra.text(entity_id) }
      }
    )
  end

  local insert_cql = "INSERT INTO tags (tag, entity_name, entity_id, other_tags) VALUES (?, ?, ?, ?)"
  if ttl then
    insert_cql = insert_cql .. fmt(" USING TTL %u", ttl)
  end
  for _, tag in ipairs(tags_to_add) do
    insert(cqls,
      {
        insert_cql,
        { cassandra.text(tag), cassandra.text(schema.name), cassandra.text(entity_id), cassandra.set(new_tags) }
      }
    )
  end

  local delete_cql = "DELETE FROM tags WHERE tag=? AND entity_name=? and entity_id=?"
  if ttl then
    delete_cql = delete_cql .. fmt(" USING TTL %u", ttl)
  end
  for _, tag in ipairs(tags_to_delete) do
    insert(cqls,
      {
        delete_cql,
        { cassandra.text(tag), cassandra.text(schema.name), cassandra.text(entity_id) }
      }
    )
  end

  return cqls, nil
end


function _M.new(connector, schema, errors)
  local n_fields         = #schema.fields
  local n_pk             = #schema.primary_key

  local each_pk_field
  local each_non_pk_field
  local ttl_field

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

    ttl_field = function()
      return schema.ttl and non_pk_fields[1] and non_pk_fields[1].field_name
    end
  end

  -- self instanciation

  local self = {
    connector               = connector, -- instance of kong.db.strategies.cassandra.init
    schema                  = schema,
    errors                  = errors,
    each_pk_field           = each_pk_field,
    each_non_pk_field       = each_non_pk_field,
    ttl_field               = ttl_field,
    foreign_keys_db_columns = {},
    queries                 = nil,
  }

  -- foreign keys constraints and page_for_ selector methods

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
              col_name           = field_name .. "_" .. foreign_pk[i],
              foreign_field      = foreign_field,
              foreign_field_name = foreign_field_name,
            })
          end
        end
      end

      local db_columns_args_names = new_tab(#db_columns, 0)

      for i = 1, #db_columns do
        -- keep args_names for 'page_for_*' methods
        db_columns_args_names[i] = db_columns[i].col_name .. " = ?"
      end

      db_columns.args_names = concat(db_columns_args_names, " AND ")

      self.foreign_keys_db_columns[field_name] = db_columns
    end
  end

  -- generate page_for_ method for inverse selection
  -- e.g. routes:page_for_service(service_pk)
  for field_name, field in schema:each_field() do
    if field.type == "foreign" then

      local method_name = "page_for_" .. field_name
      local db_columns = self.foreign_keys_db_columns[field_name]

      local select_foreign_bind_args = {}
      for _, foreign_key_column in ipairs(db_columns) do
        insert(select_foreign_bind_args, foreign_key_column.col_name .. " = ?")
      end

      self[method_name] = function(self, foreign_key, size, offset, options)
        return self:page(size, offset, options, foreign_key, db_columns)
      end
    end
  end

  return setmetatable(self, _mt)
end


local function deserialize_aggregates(value, field)
  if field.type == "record" then
    if type(value) == "string" then
      value = cjson.decode(value)
    end

  elseif field.type == "set" then
    if type(value) == "table" then
      for i = 1, #value do
        value[i] = deserialize_aggregates(value[i], field.elements)
      end
    end
  end

  if value == nil then
    return null
  end

  return value
end


function _mt:deserialize_row(row)
  if not row then
    error("row must be a table", 2)
  end

  -- deserialize rows
  -- replace `nil` fields with `ngx.null`
  -- replace `foreign_key` with `foreign = { key = "" }`
  -- return timestamps in seconds instead of ms

  for field_name, field in self.schema:each_field() do
    if field.type == "foreign" then
      local db_columns = self.foreign_keys_db_columns[field_name]

      local has_fk
      row[field_name] = new_tab(0, #db_columns)

      for i = 1, #db_columns do
        local col_name = db_columns[i].col_name

        if row[col_name] ~= nil then
          row[field_name][db_columns[i].foreign_field_name] = row[col_name]
          row[col_name] = nil

          has_fk = true
        end
      end

      if not has_fk then
        row[field_name] = null
      end

    elseif field.timestamp and row[field_name] ~= nil then
      row[field_name] = row[field_name] / 1000

    else
      row[field_name] = deserialize_aggregates(row[field_name], field)
    end
  end

  return row
end


local function _select(self, cql, args)
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

  return self:deserialize_row(row)
end


local function check_unique(self, primary_key, entity, field_name)
  -- a UNIQUE constaint is set on this field.
  -- We unfortunately follow a read-before-write pattern in this case,
  -- but this is made necessary for Kong to behave in a
  -- database-agnostic fashion between its supported RDBMs and
  -- Cassandra.
  local row, err_t = self:select_by_field(field_name, entity[field_name])
  if err_t then
    return nil, err_t
  end

  if row then
    for _, pk_field_name in self.each_pk_field() do
      if primary_key[pk_field_name] ~= row[pk_field_name] then
        -- already exists
        if field_name == "cache_key" then
          local keys = {}
          local schema = self.schema
          for _, k in ipairs(schema.cache_key) do
            local field = schema.fields[k]
            if field.type == "foreign" and entity[k] ~= ngx.null then
              keys[k] = field.schema:extract_pk_values(entity[k])
            else
              keys[k] = entity[k]
            end
          end
          return nil, self.errors:unique_violation(keys)
        end

        return nil, self.errors:unique_violation {
          [field_name] = entity[field_name],
        }
      end
    end
  end

  return true
end


function _mt:insert(entity, options)
  local schema = self.schema
  local args = new_tab(#schema.fields, 0)
  local ttl = schema.ttl and options and options.ttl
  local composite_cache_key = schema.cache_key and #schema.cache_key > 1
  local primary_key

  local cql_batch
  local batch_mode

  local mode = 'insert'

  if schema.fields.tags then
    primary_key = schema:extract_pk_values(entity)
    local err_t
    cql_batch, err_t = build_tags_cql(self, primary_key, schema, entity["tags"], ttl, false)
    if err_t then
      return nil, err_t
    end

    if cql_batch then
      -- Batch with conditions cannot span multiple tables
      -- Note this will also disables the APPLIED_COLUMN check
      mode = 'insert_no_transaction'
      batch_mode = true
    end
  end

  local cql, err
  if ttl then
    cql, err = get_query(self, mode .. "_ttl")
    if err then
      return nil, err
    end

    cql = fmt(cql, ttl)

  else
    cql, err = get_query(self, mode)
    if err then
      return nil, err
    end
  end

  -- serialize VALUES clause args

  for field_name, field in schema:each_field() do
    if field.type == "foreign" then
      local foreign_pk = entity[field_name]

      if foreign_pk ~= null then
        -- if given, check if this foreign entity exists
        local exists, err_t = foreign_pk_exists(self, field_name, field, foreign_pk)
        if not exists then
          return nil, err_t
        end
      end

      local db_columns = self.foreign_keys_db_columns[field_name]
      serialize_foreign_pk(db_columns, args, nil, foreign_pk)

    else
      if field.unique
        and entity[field_name] ~= null
        and entity[field_name] ~= nil
      then
        -- a UNIQUE constaint is set on this field.
        -- We unfortunately follow a read-before-write pattern in this case,
        -- but this is made necessary for Kong to behave in a database-agnostic
        -- fashion between its supported RDBMs and Cassandra.
        primary_key = primary_key or schema:extract_pk_values(entity)
        local _, err_t = check_unique(self, primary_key, entity, field_name)
        if err_t then
          return nil, err_t
        end
      end

      insert(args, serialize_arg(field, entity[field_name]))
    end
  end

  if composite_cache_key then
    primary_key = primary_key or schema:extract_pk_values(entity)
    local _, err_t = check_unique(self, primary_key, entity, "cache_key")
    if err_t then
      return nil, err_t
    end

    insert(args, serialize_arg(cache_key_field, entity["cache_key"]))
  end

  -- execute query

  local res, err
  if batch_mode then
    -- insert the cql to current entity table at first position
    insert(cql_batch, 1, {cql, args})
    res, err = self.connector:batch(cql_batch, nil, "write", true)
  else
    res, err = self.connector:query(cql, args, nil, "write")
  end

  if not res then
    return nil, self.errors:database_error("could not execute insertion query: "
                                           .. err)
  end

  -- check for linearizable consistency (Paxos)
  -- in batch_mode, we currently don't know the APPLIED_COLUMN
  if not batch_mode and res[1][APPLIED_COLUMN] == false then
    -- lightweight transaction (IF NOT EXISTS) failed,
    -- retrieve PK values for the PK violation error
    primary_key = primary_key or schema:extract_pk_values(entity)

    return nil, self.errors:primary_key_violation(primary_key)
  end

  -- return foreign key as if they were fetched from :select()
  -- this means foreign relationship tables should only contain
  -- the primary key of the foreign entity

  clear_tab(res)

  for field_name, field in schema:each_field() do
    local value = entity[field_name]

    if field.type == "foreign" then
      if value ~= null and value ~= nil then
        value = field.schema:extract_pk_values(value)

      else
        value = null
      end
    end

    res[field_name] = value
  end

  return res
end


function _mt:select(primary_key, options)
  local schema = self.schema
  local cql, err = get_query(self, "select")
  if err then
    return nil, err
  end
  local args = new_tab(#schema.primary_key, 0)

  -- serialize WHERE clause args

  for i, field_name, field in self.each_pk_field() do
    args[i] = serialize_arg(field, primary_key[field_name])
  end

  -- execute query

  return _select(self, cql, args)
end


function _mt:select_by_field(field_name, field_value, options)
  local cql, err = get_query(self, "select_with_filter")
  if err then
    return nil, err
  end

  local field
  if field_name == "cache_key" then
    field = cache_key_field
  else
    field = self.schema.fields[field_name]
    if field
      and field.reference
      and self.foreign_keys_db_columns[field_name]
      and self.foreign_keys_db_columns[field_name][1]
    then
      field_name = self.foreign_keys_db_columns[field_name][1].col_name
    end
  end

  local select_cql = fmt(cql, field_name .. " = ?")
  local bind_args = new_tab(1, 0)
  bind_args[1] = serialize_arg(field, field_value)

  return _select(self, select_cql, bind_args)
end


do

  local function execute_page(self, cql, args, offset, opts)
    local rows, err = self.connector:query(cql, args, opts, "read")
    if not rows then
      if err:match("Invalid value for the paging state") then
        return nil, self.errors:invalid_offset(offset, err)
      end
      return nil, self.errors:database_error("could not execute page query: "
                                              .. err)
    end

    local next_offset
    if rows.meta and rows.meta.paging_state then
      next_offset = rows.meta.paging_state
    end

    rows.meta = nil
    rows.type = nil

    return rows, nil, next_offset
  end

  local function query_page(self, offset, foreign_key, foreign_key_db_columns, opts)
    local cql
    local args
    local err

    if not foreign_key then
      cql, err = get_query(self, "select_page")
      if err then
        return nil, err
      end

    elseif foreign_key and foreign_key_db_columns then
      args = new_tab(#foreign_key_db_columns, 0)
      cql, err = get_query(self, "select_with_filter")
      if err then
        return nil, err
      end
      cql = fmt(cql, foreign_key_db_columns.args_names)

      serialize_foreign_pk(foreign_key_db_columns, args, nil, foreign_key)

    else
      error("should provide both of: foreign_key, foreign_key_db_columns", 2)
    end

    local rows, err_t, next_offset = execute_page(self, cql, args, offset, opts)

    if err_t then
      return nil, err_t
    end

    for i = 1, #rows do
      rows[i] = self:deserialize_row(rows[i])
    end

    return rows, nil, next_offset and encode_base64(next_offset)
  end

  --[[
  Define the max rounds of queries we will send when filtering entity with
  tags
  For each "round" with AND we send queries at max to the number of tags provided and
  filter in Lua land with entities with all tags provided; for OR we send one request
  each round.
  Depending on the distribution of tags attached to entity, it might be possible
  that number of tags attached with one tag and doesn't has others is larger
  than the page size provided. In such case, we limit the "rounds" of such
  filtering and thus limit the total number of queries we send per paging
  request to be at most (number of tags) * PAGING_MAX_QUERY_ROUNDS
  Note the number here may not suite all conditions. If the paging request
  returns too less results, this limit can be bumped up. To archieve less
  latency for the Admin paging API, this limit can be decreased.
  ]]--
  local PAGING_MAX_QUERY_ROUNDS = 20

  -- helper function used in query_page_for_tags to translate
  -- a row with entity_id with an entity
  local function dereference_rows(self, entity_ids, entity_count)
    if not entity_ids then
      return {}, nil, nil
    end
    local entity_index = 0
    entity_count = entity_count or #entity_ids
    local entities = new_tab(entity_count, 0)
    -- TODO: send one query using IN
    for i, row in ipairs(entity_ids) do
      -- TODO: pk name id is hardcoded
      local entity, err, err_t = self:select{ id = row.entity_id }
      if err then
        return nil, err, err_t
      end
      if entity then
        entity_index = entity_index + 1
        entities[entity_index] = entity
      end
    end
    return entities, nil, nil
  end

  local function query_page_for_tags(self, size, offset, tags, cond, opts)
    -- TODO: if we don't sort, we can have a performance guidance to user
    -- to "always put tags with less entity at the front of query"
    table.sort(tags)

    local tags_count = #tags
    -- merge the condition of only one tags to be "and" condition
    local cond_or = cond == "or" and tags_count > 1

    local cql
    local args

    local next_offset = opts.paging_state

    local tags_hash = new_tab(0, tags_count)
    local cond_and_cql_first, cond_and_cql_next

    if cond_or then
      cql = get_query(self, "select_tags_cond_or")
      args = { cassandra.list(tags) }
      for _, tag in ipairs(tags) do
        tags_hash[tag] = true
      end
    else
      cond_and_cql_first = get_query(self, "select_tags_cond_and_first_tag")
      cond_and_cql_next = get_query(self, "select_tags_cond_and_next_tags")
    end

    -- the entity_ids to return
    local entity_ids = new_tab(size, 0)
    local entity_count = 0

    -- a temporary table for current query
    local current_entity_ids = new_tab(size, 0)


    local rows, err_t

    for _=1, PAGING_MAX_QUERY_ROUNDS, 1 do
      local current_next_offset
      local current_entity_count = 0

      if cond_or then
        rows, err_t, next_offset = execute_page(self, cql, args, offset, opts)
        if err_t then
          return nil, err_t, nil
        end

        clear_tab(current_entity_ids)

        for _, row in ipairs(rows) do
          local row_tag = row.tag
          local duplicated = false
          for _, attached_tag in ipairs(row.other_tags) do
            -- To ensure we don't add same entity_id twice (during current
            -- admin api request or across different requests), we only add
            -- entity_id when it first appears in the result set.
            -- That means we don't add current row if row.tag
            -- 1. is a matching tag towards provided tags (that means this
            --    entity_id can potentially be duplicated), and
            -- 2. is not the alphabetically smallest tag among all its tags
            --    (as in row.other_tags)
            if tags_hash[attached_tag] and attached_tag < row_tag then
              duplicated = true
              break
            end
          end

          if not duplicated then
            current_entity_count = current_entity_count + 1
            current_entity_ids[current_entity_count] = row.entity_id
          end
        end
      else
        for i=1, #tags, 1 do
          local tag = tags[i]

          if i == 1 then
            opts.paging_state = next_offset
            cql = cond_and_cql_first
            -- TODO: cache me
            args = { cassandra.text(tag) }
          else
            opts.paging_state = nil
            cql = cond_and_cql_next
            -- TODO: cache me
            args = { cassandra.text(tag), cassandra.list(current_entity_ids) }
          end

          rows, err_t, current_next_offset = execute_page(self, cql, args, nil, opts)

          if err_t then
            return nil, err_t, nil
          end


          if i == 1 then
            next_offset = current_next_offset
          end

          -- No rows left, stop filtering
          if not rows or #rows == 0 then
            current_entity_count = 0
            break
          end

          clear_tab(current_entity_ids)
          current_entity_count = 0
          for i, row in ipairs(rows) do
            current_entity_count = current_entity_count + 1
            current_entity_ids[current_entity_count] = row.entity_id
          end
        end
      end

      if current_entity_count > 0 then
        for i=1, current_entity_count do
          entity_count = entity_count + 1
          entity_ids[entity_count] = { entity_id = current_entity_ids[i] }
          if entity_count >= size then
            -- shouldn't be "larger than" actually
            break
          end
        end

        if entity_count < size then
          -- next time we only read what we left
          -- to return a row with length of `size`
          opts.page_size = size - entity_count
        end
      end

      -- break the loop either we read enough rows
      -- or no more data available in the datastore
      if entity_count >= size or not next_offset then
        break
      end
    end

    local entities, err_t = dereference_rows(self, entity_ids, entity_count)

    if err_t then
      return nil, err_t, nil
    end

    if next_offset and entity_count < size then
      -- Note: don't cache ngx.log so we can test in 02-intergration/07-tags_spec.lua
      ngx.log(ngx.WARN, "maximum ", PAGING_MAX_QUERY_ROUNDS, " rounds exceeded ",
              "without retrieving required size of rows, ",
              "consider lower the sparsity of tags, or increase the paging size per request"
      )
    end

    return entities, nil, next_offset and encode_base64(next_offset)
  end

  function _mt:page(size, offset, options, foreign_key, foreign_key_db_columns)
    local opts = new_tab(0, 2)
    if not size then
      size = self.connector:get_page_size(options)
    end

    if offset then
      local offset_decoded = decode_base64(offset)
      if not offset_decoded then
        return nil, self.errors:invalid_offset(offset, "bad base64 encoding")
      end

      offset = offset_decoded
    end

    opts.page_size = size
    opts.paging_state = offset

    if options and options.tags then
      return query_page_for_tags(self, size, offset, options.tags, options.tags_cond, opts)
    end

    return query_page(self, offset, foreign_key, foreign_key_db_columns, opts)
  end
end


do
  local function update(self, primary_key, entity, mode, options)
    local schema = self.schema
    local ttl = schema.ttl and options and options.ttl
    local composite_cache_key = schema.cache_key and #schema.cache_key > 1

    local cql_batch
    local batch_mode

    if schema.fields.tags then
      local err_t
      cql_batch, err_t = build_tags_cql(self, primary_key, schema, entity["tags"], ttl, true)
      if err_t then
        return nil, err_t
      end

      if cql_batch then
        -- Batch with conditions cannot span multiple tables
        -- Note this will also disables the APPLIED_COLUMN check
        mode = 'upsert'
        batch_mode = true
      end
    end


    local query_name
    if ttl then
      query_name = mode .. "_ttl"
    else
      query_name = mode
    end


    local cql, err = get_query(self, query_name)
    if err then
      return nil, err
    end

    local args = new_tab(#schema.fields, 0)
    local args_names = new_tab(#schema.fields, 0)

    -- serialize SET clause args

    for _, field_name, field in self.each_non_pk_field() do
      if entity[field_name] ~= nil then
        if field.unique and entity[field_name] ~= null then
          local _, err_t = check_unique(self, primary_key, entity, field_name)
          if err_t then
            return nil, err_t
          end
        end

        if field.type == "foreign" then
          local foreign_pk = entity[field_name]

          if foreign_pk ~= null then
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

    if composite_cache_key then
      local _, err_t = check_unique(self, primary_key, entity, "cache_key")
      if err_t then
        return nil, err_t
      end

      insert(args, serialize_arg(cache_key_field, entity["cache_key"]))
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

    if composite_cache_key then
      insert(update_columns_binds, "cache_key = ?")
    end

    if ttl then
      cql = fmt(cql, ttl, concat(update_columns_binds, ", "))
    else
      cql = fmt(cql, concat(update_columns_binds, ", "))
    end

    -- execute query
    local res, err
    if batch_mode then
      -- insert the cql to current entity table at first position
      insert(cql_batch, 1, {cql, args})
      res, err = self.connector:batch(cql_batch, nil, "write", true)
    else
      res, err = self.connector:query(cql, args, nil, "write")
    end

    if not res then
      return nil, self.errors:database_error("could not execute update query: "
                                             .. err)
    end

    if not batch_mode and mode == "update" and res[1][APPLIED_COLUMN] == false then
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


  local function update_by_field(self, field_name, field_value, entity, mode, options)
    local row, err_t = self:select_by_field(field_name, field_value)
    if err_t then
      return nil, err_t
    end

    if not row then
      if mode == "upsert" then
        row = entity
        row[field_name] = field_value

      else
        return nil, self.errors:not_found_by_field({
          [field_name] = field_value,
        })
      end
    end

    local pk = self.schema:extract_pk_values(row)

    return self[mode](self, pk, entity, options)
  end


  function _mt:update(primary_key, entity, options)
    return update(self, primary_key, entity, "update", options)
  end


  function _mt:upsert(primary_key, entity, options)
    return update(self, primary_key, entity, "upsert", options)
  end


  function _mt:update_by_field(field_name, field_value, entity, options)
    return update_by_field(self, field_name, field_value, entity, "update", options)
  end


  function _mt:upsert_by_field(field_name, field_value, entity, options)
    return update_by_field(self, field_name, field_value, entity, "upsert", options)
  end
end


do
  local function select_by_foreign_key(self, foreign_schema,
                                       foreign_field_name, foreign_key)
    local n_fields = #foreign_schema.fields
    local strategy = _M.new(self.connector, foreign_schema, self.errors)
    local cql, err = get_query(strategy, "select_with_filter")
    if err then
      return nil, err
    end
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

    return _select(strategy, cql, args)
  end


  function _mt:delete(primary_key, options)
    local schema = self.schema
    local cql, err = get_query(self, "delete")
    if err then
      return nil, err
    end
    local args = new_tab(#schema.primary_key, 0)

    local constraints = schema:get_constraints()
    for i = 1, #constraints do
      local constraint = constraints[i]
      -- foreign keys could be pointing to this entity
      -- this mimics the "ON DELETE" constraint of supported
      -- RDBMs (e.g. PostgreSQL)
      --
      -- The possible behaviors on such a constraint are:
      --  * RESTRICT (default)
      --  * CASCADE  (on_delete = "cascade", NYI)
      --  * SET NULL (NYI)

      local behavior = constraint.on_delete or "restrict"

      if behavior == "restrict" then

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

      elseif behavior == "cascade" then

        local strategy = _M.new(self.connector, constraint.schema, self.errors)
        local method = "page_for_" .. constraint.field_name

        local pager = function(size, offset)
          return strategy[method](strategy, primary_key, size, offset)
        end
        for row, err in iteration.by_row(self, pager) do
          if err then
            return nil, self.errors:database_error("could not gather " ..
                                                   "associated entities " ..
                                                   "for delete cascade: " .. err)
          end

          local row_pk = constraint.schema:extract_pk_values(row)
          local _
          _, err = strategy:delete(row_pk)
          if err then
            return nil, self.errors:database_error("could not cascade " ..
                                                   "delete entity: " .. err)
          end
        end
      end
    end

    -- serialize WHERE clause args

    for i, field_name, field in self.each_pk_field() do
      args[i] = serialize_arg(field, primary_key[field_name])
    end

    local cql_batch, err_t = build_tags_cql(self, primary_key, self.schema, {}, nil, true)
    if err_t then
      return nil, err_t
    end

    -- execute query
    local res, err
    if cql_batch then
      insert(cql_batch, 1, {cql, args} )
      res, err = self.connector:batch(cql_batch, nil, "write", true)
    else
      res, err = self.connector:query(cql, args, nil, "write")
    end


    if not res then
      return nil, self.errors:database_error("could not execute deletion query: "
                                             .. err)
    end

    return true
  end
end


function _mt:delete_by_field(field_name, field_value, options)
  local row, err_t = self:select_by_field(field_name, field_value)
  if err_t then
    return nil, err_t
  end

  if not row then
    return true
  end

  local pk = self.schema:extract_pk_values(row)

  return self:delete(pk, options)
end


function _mt:truncate(options)
  return self.connector:truncate_table(self.schema.name, options)
end


return _M
