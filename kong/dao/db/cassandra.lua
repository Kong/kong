local timestamp = require "kong.tools.timestamp"
local cassandra = require "cassandra"
local Cluster = require "resty.cassandra.cluster"
local Errors = require "kong.dao.errors"
local db_errors = require "kong.db.errors"
local utils = require "kong.tools.utils"
local cjson = require "cjson"

local tonumber = tonumber
local concat = table.concat
local match = string.match
local fmt = string.format
local uuid = utils.uuid
local pairs = pairs
local ipairs = ipairs

local _M = require("kong.dao.db").new_db("cassandra")

-- expose cassandra binding serializers
-- ex: cassandra.uuid('')
_M.cassandra = cassandra

_M.dao_insert_values = {
  id = function()
    return uuid()
  end,
  timestamp = function()
    -- return time in UNIT millisecond, and PRECISION millisecond
    return math.floor(timestamp.get_utc_ms())
  end
}

_M.additional_tables = {
  "cluster_events",
  "routes",
  "services",
  "consumers",
  "certificates",
  "snis",
}

function _M.new(kong_config)
  local self = _M.super.new()

  local query_opts = {
    consistency = cassandra.consistencies[kong_config.cassandra_consistency:lower()],
    prepared = true
  }

  if not ngx.shared.kong_cassandra then
    error("cannot use Cassandra datastore: missing shared dict "            ..
          "'kong_cassandra' in Nginx configuration, are you using a "       ..
          "custom template? Make sure the 'lua_shared_dict kong_cassandra " ..
          "[SIZE];' directive is defined.")
  end

  local cluster_options = {
    shm = "kong_cassandra",
    contact_points = kong_config.cassandra_contact_points,
    default_port = kong_config.cassandra_port,
    keyspace = kong_config.cassandra_keyspace,
    timeout_connect = kong_config.cassandra_timeout,
    timeout_read = kong_config.cassandra_timeout,
    max_schema_consensus_wait = kong_config.cassandra_schema_consensus_timeout,
    ssl = kong_config.cassandra_ssl,
    verify = kong_config.cassandra_ssl_verify,
    cafile = kong_config.lua_ssl_trusted_certificate,
    lock_timeout = 30,
    silent = ngx.IS_CLI,
  }

  if ngx.IS_CLI then
    local policy = require("resty.cassandra.policies.reconnection.const")
    cluster_options.reconn_policy = policy.new(100)

    -- Force LuaSocket usage in order to allow for self-signed certificates
    -- to be trusted (via opts.cafile) in the resty-cli interpreter.
    -- As usual, LuaSocket is also forced in non-supported cosocket contexts.
    local socket = require "cassandra.socket"
    socket.force_luasocket("timer", true)
  end

  --
  -- cluster options from Kong config
  --

  if kong_config.cassandra_username and kong_config.cassandra_password then
    cluster_options.auth = cassandra.auth_providers.plain_text(
      kong_config.cassandra_username,
      kong_config.cassandra_password
    )
  end

  if kong_config.cassandra_lb_policy == "RoundRobin" then
    local policy = require("resty.cassandra.policies.lb.rr")
    cluster_options.lb_policy = policy.new()
  elseif kong_config.cassandra_lb_policy == "RequestRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.req_rr")
    cluster_options.lb_policy = policy.new()
  elseif kong_config.cassandra_lb_policy == "DCAwareRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.dc_rr")
    cluster_options.lb_policy = policy.new(kong_config.cassandra_local_datacenter)
  elseif kong_config.cassandra_lb_policy == "RequestDCAwareRoundRobin" then
    local policy = require("resty.cassandra.policies.lb.req_dc_rr")
    cluster_options.lb_policy = policy.new(kong_config.cassandra_local_datacenter)
  end

  local cluster, err = Cluster.new(cluster_options)
  if not cluster then
    return nil, err
  end

  self.cluster = cluster
  self.query_options = query_opts
  self.cluster_options = cluster_options

  return self
end

local function extract_major(release_version)
  return match(release_version, "^(%d+)%.%d")
end

local function extract_major_minor(release_version)
  return match(release_version, "^(%d+%.%d+)")
end

local function cluster_release_version(peers)
  local major_minor_version
  local major_version
  local mismatch

  for i = 1, #peers do
    local release_version = peers[i].release_version
    if not release_version then
      return nil, 'no release_version for peer ' .. peers[i].host
    end

    local peer_major_version = extract_major(release_version)
    if not peer_major_version then
      return nil, 'failed to extract major version for peer ' .. peers[i].host ..
                  ' version: ' .. tostring(peers[i].release_version)
    end

    if i == 1 then
      major_version = peer_major_version
      major_minor_version = extract_major_minor(release_version)

    elseif peer_major_version ~= major_version then
      mismatch = true
      break
    end
  end

  if mismatch then
    local err_t = {
      "different major versions detected (only all of 2.x or 3.x supported):"
    }
    for i = 1, #peers do
      err_t[#err_t+1] = fmt("%s (%s)", peers[i].host, peers[i].release_version)
    end

    return nil, concat(err_t, " ")
  end

  return {
    major = major_version,
    major_minor = major_minor_version,
  }
end

_M.extract_major = extract_major
_M.extract_major_minor = extract_major_minor
_M.cluster_release_version = cluster_release_version

function _M:init()
  local ok, err = self.cluster:refresh()
  if not ok then
    return nil, err
  end

  local peers, err = self.cluster:get_peers()
  if err then return nil, err
  elseif not peers then return nil, 'no peers in shm' end

  local res, err = cluster_release_version(peers)
  if not res then
    return nil, err
  end

  self.major_version_n = tonumber(res.major)
  self.major_minor_version = res.major_minor

  return true
end

function _M:infos()
  return {
    db_name = "Cassandra",
    desc = "keyspace",
    name = self.cluster_options.keyspace,
    version = self.major_minor_version or "unknown",
  }
end

local function deserialize_rows(rows, schema)
  for i, row in ipairs(rows) do
    for col, value in pairs(row) do
      if schema.fields[col] then
        local t = schema.fields[col].type
        if t == "table" or t == "array" then
          rows[i][col] = cjson.decode(value)
        end
      end
    end
  end
end

local coordinator

function _M:first_coordinator()
  local peer, err = self.cluster:first_coordinator()
  if not peer then
    return nil, err
  end

  coordinator = peer

  return true
end

function _M:get_coordinator()
  if not coordinator then
    return nil, "no coordinator has been set"
  end

  return coordinator
end

function _M:coordinator_change_keyspace(keyspace)
  if not coordinator then
    return nil, "no coordinator"
  end

  return coordinator:change_keyspace(keyspace)
end

function _M:close_coordinator()
  if not coordinator then
    return nil, "no coordinator"
  end

  local _, err = coordinator:close()
  if err then
    return nil, err
  end

  coordinator = nil

  return true
end

function _M:check_schema_consensus()
  local close_coordinator

  if not coordinator then
    close_coordinator = true

    local peer, err = self:first_coordinator()
    if not peer then
      return nil, "could not retrieve coordinator: " .. err
    end

    -- coordinator = peer -- done by first_coordinator()
  end

  local ok, err = self.cluster.check_schema_consensus(coordinator)

  if close_coordinator then
    -- ignore errors
    self:close_coordinator()
  end

  if err then
    return nil, err
  end

  return ok
end

-- timeout is optional, defaults to `max_schema_consensus_wait` setting
function _M:wait_for_schema_consensus(timeout)
  if not coordinator then
    return nil, "no coordinator"
  end

  return self.cluster:wait_schema_consensus(coordinator, timeout)
end

function _M:query(query, args, options, schema, no_keyspace)
  local opts = self:clone_query_options(options)
  local coordinator_opts = {}
  if no_keyspace then
    coordinator_opts.no_keyspace = true
  end

  if coordinator then
    local res, err = coordinator:execute(query, args, coordinator_opts)
    if not res then
      return nil, Errors.db(err)
    end

    return res
  end

  local res, err = self.cluster:execute(query, args, opts, coordinator_opts)
  if not res then
    return nil, Errors.db(err)
  end

  if schema and res.type == "ROWS" then
    deserialize_rows(res, schema)
  end

  return res
end

--- Query building
-- @section query_building

local function serialize_arg(field, value)
  if value == nil or value == ngx.null then
    return cassandra.null
  elseif field.type == "id" then
    return cassandra.uuid(value)
  elseif field.type == "timestamp" then
    return cassandra.timestamp(value)
  elseif field.type == "boolean" then
    if type(value) == "boolean" then
      return cassandra.boolean(value)
    end

    return cassandra.boolean(value == "true")
  elseif field.type == "table" or field.type == "array" then
    return cjson.encode(value)
  else
    return value
  end
end

local function get_where(schema, filter_keys, args)
  args = args or {}
  local where = {}
  local fields = schema.fields

  for col, value in pairs(filter_keys) do
    where[#where+1] = col .. " = ?"
    args[#args+1] = serialize_arg(fields[col], value)
  end

  return concat(where, " AND "), args
end

local function select_query(table_name, where, select_clause)
  select_clause = select_clause or "*"

  local query = fmt("SELECT %s FROM %s", select_clause, table_name)

  if where then
    query = query .. " WHERE " .. where .. " ALLOW FILTERING"
  end

  return query
end

--- Querying
-- @section querying

local function check_unique_constraints(self, table_name, constraints, values, primary_keys, update)
  local errors

  for col, constraint in pairs(constraints.unique) do
    -- Only check constraints if value is non-null
    if values[col] ~= nil and values[col] ~= ngx.null then
      local where, args = get_where(constraint.schema, {[col] = values[col]})
      local query = select_query(table_name, where)
      local rows, err = self:query(query, args, nil, constraint.schema)
      if err then return nil, err
      elseif #rows > 0 then
        -- if in update, it's fine if the retrieved row is
        -- the same as the one being updated
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

  return errors == nil, Errors.unique(errors)
end


local function check_foreign_key_in_new_db(new_dao, primary_key)
  local entity, err, err_t = new_dao:select(primary_key)

  if err then
    if err_t.code == db_errors.codes.DATABASE_ERROR then
      return false, Errors.db(err)
    end

    return false, Errors.schema(err_t)
  end

  if entity then
    return entity
  end

  return false
end


local function check_foreign_constraints(self, values, constraints)
  local errors

  for col, constraint in pairs(constraints.foreign) do
    -- Only check foreign keys if value is non-null,
    -- if must not be null, field should be required
    if values[col] ~= nil and values[col] ~= ngx.null then

      if self.new_db[constraint.table] then
        -- new DAO
        local new_dao = self.new_db[constraint.table]
        local res, err = check_foreign_key_in_new_db(new_dao, {
          [constraint.col] = values[col]
        })
        if err then return nil, err
        elseif not res then
          errors = utils.add_error(errors, col, values[col])
        end

      else
        -- old DAO
        local res, err = self:find(constraint.table, constraint.schema, {
          [constraint.col] = values[col]
        })
        if err then return nil, err
        elseif not res then
          errors = utils.add_error(errors, col, values[col])
        end
      end

    end
  end

  return errors == nil, Errors.foreign(errors)
end

function _M:insert(table_name, schema, model, constraints, options)
  options = options or {}

  local ok, err = check_unique_constraints(self, table_name, constraints, model)
  if not ok then
    return nil, err
  end

  ok, err = check_foreign_constraints(self, model, constraints)
  if not ok then
    return nil, err
  end

  local cols, binds, args = {}, {}, {}

  for col, value in pairs(model) do
    local field = schema.fields[col]
    cols[#cols+1] = col
    args[#args+1] = serialize_arg(field, value)
    binds[#binds+1] = "?"
  end

  local query = fmt("INSERT INTO %s(%s) VALUES(%s)%s",
                    table_name,
                    concat(cols, ", "),
                    concat(binds, ", "),
                    options.ttl and fmt(" USING TTL %d", options.ttl) or "")

  local res, err = self:query(query, args)
  if not res then
    return nil, err
  end

  local primary_keys = model:extract_keys()

  return self:find(table_name, schema, primary_keys)
end

function _M:find(table_name, schema, filter_keys)
  local where, args = get_where(schema, filter_keys)
  local query = select_query(table_name, where)
  local rows, err = self:query(query, args, nil, schema)
  if not rows then       return nil, err
  elseif #rows <= 1 then return rows[1]
  else                   return nil, "bad rows result" end
end

function _M:find_all(table_name, tbl, schema)
  local opts = self:clone_query_options()
  local where, args
  if tbl then
    where, args = get_where(schema, tbl)
  end

  local err
  local query = select_query(table_name, where)
  local res_rows = {}

  local iter = self.cluster.iterate
  local iter_self = self.cluster
  if coordinator then
    -- we are in migrations, and need to wait for a schema consensus
    -- before performing such a DML query
    local ok, err = self:wait_for_schema_consensus()
    if not ok then
      return nil, "failed waiting for schema consensus: " .. err
    end

    iter = coordinator.page_iterator
    iter_self = coordinator
    opts.prepared = false
  end

  for rows, page_err in iter(iter_self, query, args, opts) do
    if page_err then
      err = Errors.db(page_err)
      res_rows = nil
      break
    end

    if schema then
      deserialize_rows(rows, schema)
    end

    for _, row in ipairs(rows) do
      res_rows[#res_rows+1] = row
    end
  end

  return res_rows, err
end

function _M:find_page(table_name, tbl, paging_state, page_size, schema)
  local where, args
  if tbl then
    where, args = get_where(schema, tbl)
  end

  local query = select_query(table_name, where)
  local rows, err = self:query(query, args, {page_size = page_size, paging_state = paging_state}, schema)
  if not rows then
    return nil, err
  end

  local paging_state
  if rows.meta and rows.meta.has_more_pages then
    paging_state = rows.meta.paging_state
  end

  rows.meta = nil
  rows.type = nil

  return rows, nil, paging_state
end

function _M:count(table_name, tbl, schema)
  local where, args
  if tbl then
    where, args = get_where(schema, tbl)
  end

  local query = select_query(table_name, where, "COUNT(*)")
  local res, err = self:query(query, args)
  if not res then       return nil, err
  elseif #res == 1 then return res[1].count
  else                  return "bad rows result" end
end

function _M:update(table_name, schema, constraints, filter_keys, values, nils, full, model, options)
  options = options or {}

  -- must check unique constraints manually too
  local ok, err = check_unique_constraints(self, table_name, constraints, values, filter_keys, true)
  if not ok then
    return nil, err
  end

  ok, err = check_foreign_constraints(self, values, constraints)
  if not ok then
    return nil, err
  end

  -- Cassandra TTLs on update is per-column and not per-row,
  -- and TTLs cannot be updated on primary keys.
  -- TTLs can also only be incremented and not decremented.
  -- Because of these limitations, the current implementation
  -- is to use an upsert operation.
  -- See: https://issues.apache.org/jira/browse/CASSANDRA-9312
  if options.ttl then
    if schema.primary_key and
      #schema.primary_key == 1 and
      filter_keys[schema.primary_key[1]] then
      local row, err = self:find(table_name, schema, filter_keys)
      if err then return nil, err
      elseif row then
        for k, v in pairs(row) do
          if not values[k] then
            model[k] = v -- Populate the model to be used later for the insert
          end
        end
        -- insert without any constraint check, since the check has already been executed
        return self:insert(table_name, schema, model, {unique={}, foreign={}}, options)
      end
    else
      return nil, "cannot update TTL on entities that have more than one primary_key"
    end
  end

  local where
  local sets, args = {}, {}

  for col, value in pairs(values) do
    local field = schema.fields[col]
    sets[#sets+1] = col .. " = ?"
    args[#args+1] = serialize_arg(field, value)
  end

  -- unset nil fields if asked for
  if full then
    for col in pairs(nils) do
      sets[#sets + 1] = col .. " = ?"
      args[#args + 1] = cassandra.null
    end
  end

  where, args = get_where(schema, filter_keys, args)

  local query = fmt("UPDATE %s%s SET %s WHERE %s",
                    table_name,
                    options.ttl and fmt(" USING TTL %d", options.ttl) or "",
                    concat(sets, ", "),
                    where)

  local res, err = self:query(query, args)
  if not res then return nil, err
  elseif res.type == "VOID" then
    return self:find(table_name, schema, filter_keys)
  end
end

function _M:delete(table_name, schema, primary_keys, constraints)
  local row, err = self:find(table_name, schema, primary_keys)
  if not row or err then
    return nil, err
  end

  local where, args = get_where(schema, primary_keys)
  local query = fmt("DELETE FROM %s WHERE %s", table_name, where)
  local res, err =  self:query(query, args)
  if not res then return nil, err
  elseif res.type == "VOID" then
    if constraints and constraints.cascade then
      for f_entity, cascade in pairs(constraints.cascade) do
        local tbl = {[cascade.f_col] = primary_keys[cascade.col]}
        local rows, err = self:find_all(cascade.table, tbl, cascade.schema)
        if not rows then
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
    return row
  end
end

--- Migrations
-- @section migrations

function _M:queries(queries, no_keyspace)
  for _, query in ipairs(utils.split(queries, ";")) do
    query = utils.strip(query)
    if query ~= "" then
      local res, err = self:query(query, nil, {
        prepared = false,
        --consistency = cassandra.consistencies.all,
      }, nil, no_keyspace)
      if not res then
        return err
      end
    end
  end
end

function _M:drop_table(table_name)
  local res, err = self:query("DROP TABLE " .. table_name)
  if not res then
    return nil, err
  end
  return true
end

function _M:truncate_table(table_name)
  local res, err = self:query("TRUNCATE " .. table_name)
  if not res then
    return nil, err
  end
  return true
end

function _M:current_migrations()
  local q_keyspace_exists, q_migrations_table_exists

  if not self.major_version_n then
    local ok, err = self:init()
    if not ok then
      return nil, err
    end
  end

  -- For now we will assume that a release version number of 3 and greater
  -- will use the same schema. This is recognized as a hotfix and will be
  -- revisited for a more considered solution at a later time.
  if self.major_version_n >= 3 then
    q_keyspace_exists = [[
      SELECT * FROM system_schema.keyspaces
      WHERE keyspace_name = ?
    ]]
    q_migrations_table_exists = [[
      SELECT COUNT(*) FROM system_schema.tables
      WHERE keyspace_name = ? AND table_name = ?
    ]]
  else
    q_keyspace_exists = [[
      SELECT * FROM system.schema_keyspaces
      WHERE keyspace_name = ?
    ]]
    q_migrations_table_exists = [[
      SELECT COUNT(*) FROM system.schema_columnfamilies
      WHERE keyspace_name = ? AND columnfamily_name = ?
    ]]
  end

  -- Check if keyspace exists
  local rows, err = self:query(q_keyspace_exists, {
    self.cluster_options.keyspace
  }, {
    prepared = false,
    --consistency = cassandra.consistencies.all,
  }, nil, true)
  if not rows then       return nil, err
  elseif #rows == 0 then return {} end

  if coordinator then
    local keyspace = self.cluster_options.keyspace
    local ok, err = self:coordinator_change_keyspace(keyspace)
    if not ok then
      return nil, err
    end
  end

  -- Check if schema_migrations table exists
  rows, err = self:query(q_migrations_table_exists, {
    self.cluster_options.keyspace,
    "schema_migrations"
  }, {
    prepared = false,
    --consistency = cassandra.consistencies.all,
  })
  if not rows then return nil, err
  elseif rows[1] and rows[1].count > 0 then
    return self:query("SELECT * FROM schema_migrations", nil, {
      prepared = false,
      --consistency = cassandra.consistencies.all,
    })
  else return {} end
end

function _M:record_migration(id, name)
  local res, err = self:query([[
    UPDATE schema_migrations
    SET migrations = migrations + ?
    WHERE id = ?
  ]], {
    cassandra.list({ name }),
    id
  }, {
    prepared = false,
    --consistency = cassandra.consistencies.all,
  })
  if not res then
    return nil, err
  end
  return true
end

function _M:reachable()
  local peer, err = self.cluster:next_coordinator()
  if not peer then
    return nil, Errors.db(err)
  end

  peer:setkeepalive()

  return true
end

return _M
