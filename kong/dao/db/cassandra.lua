local cassandra = require "cassandra"
local Cluster = require "resty.cassandra.cluster"
local timestamp = require "kong.tools.timestamp"
local Errors = require "kong.dao.errors"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local uuid = utils.uuid

local _M = require("kong.dao.db").new_db("cassandra")

-- expose cassandra binding serializers
-- ex: cassandra.uuid('')
_M.cassandra = cassandra

_M.dao_insert_values = {
  id = function()
    return uuid()
  end,
  timestamp = function()
    return timestamp.get_utc()
  end
}

function _M.new(kong_config)
  local self = _M.super.new()

  local query_opts = {
    consistency = cassandra.consistencies[kong_config.cassandra_consistency:lower()],
    prepared = true
  }

  local cluster_options = {
    shm = "cassandra",
    contact_points = kong_config.cassandra_contact_points,
    default_port = kong_config.cassandra_port,
    keyspace = kong_config.cassandra_keyspace,
    connect_timeout = kong_config.cassandra_timeout,
    read_timeout = kong_config.cassandra_timeout,
    ssl = kong_config.cassandra_ssl,
    verify = kong_config.cassandra_ssl_verify
  }

  if kong_config.cassandra_username and kong_config.cassandra_password then
    cluster_options.auth = cassandra.auth_providers.plain_text(
      kong_config.cassandra_username,
      kong_config.cassandra_password
    )
  end

  local cluster, err = Cluster.new(cluster_options)
  if not cluster then return nil, err end

  self.cluster = cluster
  self.query_options = query_opts
  self.cluster_options = cluster_options

  if ngx.RESTY_CLI then
    -- we must manually call our init phase (usually called from `init_by_lua`)
    -- to refresh the cluster.
    local ok, err = self:init()
    if not ok then return nil, err end
  end

  return self
end

local function extract_major(release_version)
  return string.match(release_version, "^(%d+)%.%d+%.?%d*$")
end

local function cluster_release_version(peers)
  local first_release_version
  local ok = true

  for i = 1, #peers do
    local release_version = peers[i].release_version
    if not release_version then
      return nil, 'no release_version for peer '..peers[i].host
    end

    local major_version = extract_major(release_version)
    if i == 1 then
      first_release_version = major_version
    elseif major_version ~= first_release_version then
      ok = false
      break
    end
  end

  if not ok then
    local err_t = {"different major versions detected (only all of 2.x or 3.x supported):"}
    for i = 1, #peers do
      err_t[#err_t+1] = string.format("%s (%s)", peers[i].host, peers[i].release_version)
    end

    return nil, table.concat(err_t, " ")
  end

  return tonumber(first_release_version)
end

_M.extract_major = extract_major
_M.cluster_release_version = cluster_release_version

function _M:init()
  local ok, err = self.cluster:refresh()
  if not ok then return nil, err end

  local peers, err = self.cluster:get_peers()
  if err then return nil, err
  elseif not peers then return nil, 'no peers in shm' end

  self.release_version, err = cluster_release_version(peers)
  if not self.release_version then return nil, err end

  return true
end

function _M:infos()
  return {
    desc = "keyspace",
    name = self.cluster_options.keyspace
  }
end

-- Formatting

local function serialize_arg(field, value)
  if value == nil then
    return cassandra.null
  elseif field.type == "id" then
    return cassandra.uuid(value)
  elseif field.type == "timestamp" then
    return cassandra.timestamp(value)
  elseif field.type == "table" or field.type == "array" then
    return cjson.encode(value)
  else
    return value
  end
end

local function deserialize_rows(rows, schema)
  for i, row in ipairs(rows) do
    for col, value in pairs(row) do
      if schema.fields[col].type == "table" or schema.fields[col].type == "array" then
        rows[i][col] = cjson.decode(value)
      end
    end
  end
end

local function get_where(schema, filter_keys, args)
  args = args or {}
  local fields = schema.fields
  local where = {}

  for col, value in pairs(filter_keys) do
    where[#where + 1] = col.." = ?"
    args[#args + 1] = serialize_arg(fields[col], value)
  end

  return table.concat(where, " AND "), args
end

local function get_select_query(table_name, where, select_clause)
  local query = string.format("SELECT %s FROM %s", select_clause or "*", table_name)
  if where ~= nil then
    query = query.." WHERE "..where.." ALLOW FILTERING"
  end

  return query
end

--- Querying

local function check_unique_constraints(self, table_name, constraints, values, primary_keys, update)
  local errors

  for col, constraint in pairs(constraints.unique) do
    -- Only check constraints if value is non-null
    if values[col] ~= nil then
      local where, args = get_where(constraint.schema, {[col] = values[col]})
      local query = get_select_query(table_name, where)
      local rows, err = self:query(query, args, nil, constraint.schema)
      if err then
        return err
      elseif #rows > 0 then
        -- if in update, it's fine if the retrieved row is the same as the one updated
        if update then
          local same_row = true
          for col, val in pairs(primary_keys) do
            if val ~= rows[1][col] then
              same_row = false
              break
            end
          end

          if not same_row then
            errors = utils.add_error(errors, col, values[col])
          end
        else
          errors = utils.add_error(errors, col, values[col])
        end
      end
    end
  end

  return Errors.unique(errors)
end

local function check_foreign_constaints(self, values, constraints)
  local errors

  for col, constraint in pairs(constraints.foreign) do
    -- Only check foreign keys if value is non-null, if must not be null, field should be required
    if values[col] ~= nil then
      local res, err = self:find(constraint.table, constraint.schema, {[constraint.col] = values[col]})
      if err then
        return err
      elseif res == nil then
        errors = utils.add_error(errors, col, values[col])
      end
    end
  end

  return Errors.foreign(errors)
end

function _M:query(query, args, options, schema, no_keyspace)
  local opts = self:clone_query_options(options)
  local coordinator_opts = {}
  if no_keyspace then
    -- defaults to the system keyspace, always present
    coordinator_opts.keyspace = "system"
  end

  local res, err = self.cluster:execute(query, args, opts, coordinator_opts)
  if not res then
    return nil, Errors.db(err)
  end

  if schema ~= nil and res.type == "ROWS" then
    deserialize_rows(res, schema)
  end

  return res
end

function _M:insert(table_name, schema, model, constraints, options)
  local err = check_unique_constraints(self, table_name, constraints, model)
  if err then
    return nil, err
  end

  err = check_foreign_constaints(self, model, constraints)
  if err then
    return nil, err
  end

  local cols, binds, args = {}, {}, {}
  for col, value in pairs(model) do
    local field = schema.fields[col]
    cols[#cols + 1] = col
    args[#args + 1] = serialize_arg(field, value)
    binds[#binds + 1] = "?"
  end

  cols = table.concat(cols, ", ")
  binds = table.concat(binds, ", ")

  local query = string.format("INSERT INTO %s(%s) VALUES(%s)%s",
                              table_name, cols, binds, (options and options.ttl) and string.format(" USING TTL %d", options.ttl) or "")
  local err = select(2, self:query(query, args))
  if err then
    return nil, err
  end

  local primary_keys = model:extract_keys()

  local row, err = self:find(table_name, schema, primary_keys)
  if err then
    return nil, err
  end

  return row
end

function _M:find(table_name, schema, filter_keys)
  local where, args = get_where(schema, filter_keys)
  local query = get_select_query(table_name, where)
  local rows, err = self:query(query, args, nil, schema)
  if err then
    return nil, err
  elseif #rows > 0 then
    return rows[1]
  end
end

function _M:find_all(table_name, tbl, schema)
  local opts = self:clone_query_options()
  local where, args
  if tbl ~= nil then
    where, args = get_where(schema, tbl)
  end

  local err
  local query = get_select_query(table_name, where)
  local res_rows = {}

  for rows, page_err in self.cluster:iterate(query, args, opts) do
    if page_err then
      err = Errors.db(page_err)
      res_rows = nil
      break
    end
    if schema ~= nil then
      deserialize_rows(rows, schema)
    end
    for _, row in ipairs(rows) do
      res_rows[#res_rows + 1] = row
    end
  end

  return res_rows, err
end

function _M:find_page(table_name, tbl, paging_state, page_size, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_where(schema, tbl)
  end

  local query = get_select_query(table_name, where)
  local rows, err = self:query(query, args, {page_size = page_size, paging_state = paging_state}, schema)
  if err then
    return nil, err
  elseif rows ~= nil then
    local paging_state
    if rows.meta and rows.meta.has_more_pages then
      paging_state = rows.meta.paging_state
    end
    rows.meta = nil
    rows.type = nil
    return rows, nil, paging_state
  end
end

function _M:count(table_name, tbl, schema)
  local where, args
  if tbl ~= nil then
    where, args = get_where(schema, tbl)
  end

  local query = get_select_query(table_name, where, "COUNT(*)")
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and #res > 0 then
    return res[1].count
  end
end

function _M:update(table_name, schema, constraints, filter_keys, values, nils, full, model, options)
  -- must check unique constaints manually too
  local err = check_unique_constraints(self, table_name, constraints, values, filter_keys, true)
  if err then
    return nil, err
    end
  err = check_foreign_constaints(self, values, constraints)
  if err then
    return nil, err
  end

  -- Cassandra TTL on update is per-column and not per-row, and TTLs cannot be updated on primary keys.
  -- Not only that, but TTL on other rows can only be incremented, and not decremented. Because of all
  -- of these limitations, the only way to make this happen is to do an upsert operation.
  -- This implementation can be changed once Cassandra closes this issue: https://issues.apache.org/jira/browse/CASSANDRA-9312
  if options and options.ttl then
    if schema.primary_key and #schema.primary_key == 1 and filter_keys[schema.primary_key[1]] then
      local row, err = self:find(table_name, schema, filter_keys)
      if err then
        return nil, err
      elseif row then
        for k, v in pairs(row) do
          if not values[k] then
            model[k] = v -- Populate the model to be used later for the insert
          end
        end

        -- Insert without any contraint check, since the check has already been executed
        return self:insert(table_name, schema, model, {unique={}, foreign={}}, options)
      end
    else
      return nil, "Cannot update TTL on entities that have more than one primary_key"
    end
  end

  local sets, args, where = {}, {}
  for col, value in pairs(values) do
    local field = schema.fields[col]
    sets[#sets + 1] = col.." = ?"
    args[#args + 1] = serialize_arg(field, value)
  end

  -- unset nil fields if asked for
  if full then
    for col in pairs(nils) do
      sets[#sets + 1] = col.." = ?"
      args[#args + 1] = cassandra.unset
    end
  end

  sets = table.concat(sets, ", ")

  where, args = get_where(schema, filter_keys, args)
  local query = string.format("UPDATE %s%s SET %s WHERE %s",
                              table_name, (options and options.ttl) and string.format(" USING TTL %d", options.ttl) or "", sets, where)
  local res, err = self:query(query, args)
  if err then
    return nil, err
  elseif res and res.type == "VOID" then
    return self:find(table_name, schema, filter_keys)
  end
end

local function cascade_delete(self, primary_keys, constraints)
  if constraints.cascade == nil then return end

  for f_entity, cascade in pairs(constraints.cascade) do
    local tbl = {[cascade.f_col] = primary_keys[cascade.col]}
    local rows, err = self:find_all(cascade.table, tbl, cascade.schema)
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      local primary_keys_to_delete = {}
      for _, primary_key in ipairs(cascade.schema.primary_key) do
        primary_keys_to_delete[primary_key] = row[primary_key]
      end

      local ok, err = self:delete(cascade.table, cascade.schema, primary_keys_to_delete)
      if not ok then
        return nil, err
      end
    end
  end
end

function _M:delete(table_name, schema, primary_keys, constraints)
  local row, err = self:find(table_name, schema, primary_keys)
  if err or row == nil then
    return nil, err
  end

  local where, args = get_where(schema, primary_keys)
  local query = string.format("DELETE FROM %s WHERE %s",
                              table_name, where)
  local res, err =  self:query(query, args)
  if err then
    return nil, err
  elseif res and res.type == "VOID" then
    if constraints ~= nil then
      cascade_delete(self, primary_keys, constraints)
    end
    return row
  end
end

-- Migrations

function _M:queries(queries, no_keyspace)
  for _, query in ipairs(utils.split(queries, ";")) do
    if utils.strip(query) ~= "" then
      local err = select(2, self:query(query, nil, nil, nil, no_keyspace))
      if err then
        return err
      end
    end
  end
end

function _M:drop_table(table_name)
  return select(2, self:query("DROP TABLE "..table_name))
end

function _M:truncate_table(table_name)
  return select(2, self:query("TRUNCATE "..table_name))
end

function _M:current_migrations()
  local q_keyspace_exists, q_migrations_table_exists

  assert(self.release_version, "release_version not set for Cassandra cluster")

  if self.release_version == 3 then
    q_keyspace_exists = "SELECT * FROM system_schema.keyspaces WHERE keyspace_name = ?"
    q_migrations_table_exists = [[
      SELECT COUNT(*) FROM system_schema.tables
      WHERE keyspace_name = ? AND table_name = ?
    ]]
  else
    q_keyspace_exists = "SELECT * FROM system.schema_keyspaces WHERE keyspace_name = ?"
    q_migrations_table_exists = [[
      SELECT COUNT(*) FROM system.schema_columnfamilies
      WHERE keyspace_name = ? AND columnfamily_name = ?
    ]]
  end

  -- Check if keyspace exists
  local rows, err = self:query(q_keyspace_exists, {
    self.cluster_options.keyspace
  }, {prepared = false}, nil, true)
  if err then return nil, err
  elseif #rows == 0 then return {} end

  -- Check if schema_migrations table exists
  rows, err = self:query(q_migrations_table_exists, {
    self.cluster_options.keyspace,
    "schema_migrations"
  }, {prepared = false})
  if err then return nil, err end

  if rows[1].count > 0 then
    return self:query("SELECT * FROM schema_migrations", nil, {
      prepared = false
    })
  else
    return {}
  end
end

function _M:record_migration(id, name)
  return select(2, self:query([[
    UPDATE schema_migrations SET migrations = migrations + ? WHERE id = ?
  ]], {
    cassandra.list {name},
    id
  }))
end

return _M
