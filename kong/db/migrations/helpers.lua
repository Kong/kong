--local json_decode = require("cjson.safe").decode
local cassandra = require("cassandra")
--local utils = require "kong.tools.utils"


local fmt = string.format
local table_concat = table.concat


local _M = {}
_M.__index = _M


function _M.new(connector)
  if type(connector) ~= "table" then
    error("connector must be a table", 2)
  end

  return setmetatable({
    connector = connector,
  }, _M)
end


-- Iterator to update plugin configurations.
-- It works indepedent of the underlying datastore.
-- @param dao the dao to use
-- @param plugin_name the name of the plugin whos configurations
-- to iterate over
-- @return `ok+config+update` where `ok` is a boolean, `config` is the plugin configuration
-- table (or the error if not ok), and `update` is an update function to call with
-- the updated configuration table
-- @usage
--    up = function(_, _, dao)
--      for ok, config, update in plugin_config_iterator(dao, "jwt") do
--        if not ok then
--          return config
--        end
--        if config.run_on_preflight == nil then
--          config.run_on_preflight = true
--          local _, err = update(config)
--          if err then
--            return err
--          end
--        end
--      end
--    end
--[==[
function _M.plugin_config_iterator(dao, plugin_name)
  local db = dao.db.new_db

  -- iterates over rows
  local run_rows = function(t)
    for _, row in ipairs(t) do
      if type(row.config) == "string" then
        -- de-serialize in case of Cassandra
        local json, err = json_decode(row.config)
        if not json then
          return nil, ("json decoding error '%s' while decoding '%s'"):format(
                      tostring(err), tostring(row.config))
        end
        row.config = json
      end
      coroutine.yield(row.config, function(updated_config)
        if type(updated_config) ~= "table" then
          return nil, "expected table, got " .. type(updated_config)
        end
        row.created_at = nil
        row.config = updated_config
        return db.plugins:update({id = row.id}, row)
      end)
    end
    return true
  end

  local coro
  if db.strategy == "cassandra" then
    coro = coroutine.create(function()
      local coordinator = dao.db:get_coordinator()
      for rows, err in coordinator:iterate([[
                SELECT * FROM plugins WHERE name = ']] .. plugin_name .. [[';
              ]]) do
        if err then
          return nil, nil, err
        end

        assert(run_rows(rows))
      end
    end)

  elseif db.strategy == "postgres" then
    coro = coroutine.create(function()
      local rows, err = dao.db:query([[
        SELECT * FROM plugins WHERE name = ']] .. plugin_name .. [[';
      ]])
      if err then
        return nil, nil, err
      end

      assert(run_rows(rows))
    end)

  else
    coro = coroutine.create(function()
      return nil, nil, "unknown database type: " .. tostring(db.strategy)
    end)
  end

  return function()
    local coro_ok, config, update, err = coroutine.resume(coro)
    if not coro_ok then return false, config end  -- coroutine errored out
    if err         then return false, err    end  -- dao soft error
    if not config  then return nil           end  -- iterator done
    return true, config, update
  end
end
--]==]


local CASSANDRA_EXECUTE_OPTS = {
  consistency = cassandra.consistencies.all,
}


--[[
Insert records from the table defined by source_table_def into
destination_table_def. Both table_defs have the following structure
  { name    = "ssl_certificates",
    columns = {
      id         = "uuid",
      cert       = "text",
      key        = "text",
      created_at = "timestamp",
    },
    partition_keys = { "id" },
  }

columns_to_copy is a hash-like table.
* Each key must be a string D representing a column in the destination table.
* If the value is a string S, then the value of the S column in the source
  table will be assigned to the D column in destination.
* If the value is a function, then the result of executing it will be assigned
  to the D column.
Example:
  {
    partition  = function() return cassandra.text("certificates") end,
    id         = "id",
    cert       = "cert",
    key        = "key",
    created_at = "created_at",
  }

The function takes the "source row" as parameter, so it could be used to do things
like merging two fields together into one, or putting a string in uppercase.

Note: In Cassandra, INSERT does "insert if not exists or update using pks if exists"
      So this function is re-entrant
--]]
function _M:copy_cassandra_records(source_table_def,
                                   destination_table_def,
                                   columns_to_copy)
  local coordinator, err = self.connector:connect_migrations()
  if not coordinator then
    return nil, err
  end

  local cql = fmt("SELECT * FROM %s", source_table_def.name)
  for rows, err in coordinator:iterate(cql) do
    if err then
      return nil, err
    end

    for _, source_row in ipairs(rows) do
      local column_names = {}
      local values = {}
      local len = 0

      for dest_column_name, source_value in pairs(columns_to_copy) do
        if type(source_value) == "string" then
          source_value = source_row[source_value]

          local dest_type = destination_table_def.columns[dest_column_name]
          local type_converter = cassandra[dest_type]
          if not type_converter then
            return nil, fmt("Could not find the cassandra type converter for column %s (type %s)",
                            dest_column_name, source_table_def[dest_column_name])
          end

          if source_value == nil then
            source_value = cassandra.unset
          else
            source_value = type_converter(source_value)
          end

        elseif type(source_value) == "function" then
          source_value = source_value(source_row)

        else
          return nil, fmt("Expected a string or function, found %s (a %s)",
                          tostring(source_value), type(source_value))
        end

        if source_value ~= nil then
          len = len + 1
          values[len] = source_value
          column_names[len] = dest_column_name
        end
      end

      local question_marks = string.sub(string.rep("?, ", len), 1, -3)

      local insert_cql = fmt("INSERT INTO %s (%s) VALUES (%s)",
                             destination_table_def.name,
                             table_concat(column_names, ", "),
                             question_marks)

      local _, err = coordinator:execute(insert_cql, values, CASSANDRA_EXECUTE_OPTS)
      if err then
        return nil, err
      end
    end
  end

  return true
end


--[==[
do
  local function create_table_if_not_exists(coordinator, table_def)
    local partition_keys = table_def.partition_keys
    local primary_key_cql = ""
    if #partition_keys > 0 then
      primary_key_cql = fmt(", PRIMARY KEY (%s)", table_concat(partition_keys, ", "))
    end

    local column_declarations = {}
    local len = 0
    for name, typ in pairs(table_def.columns) do
      len = len + 1
      column_declarations[len] = fmt("%s %s", name, typ)
    end

    local column_declarations_cql = table_concat(column_declarations, ", ")

    local cql = fmt("CREATE TABLE IF NOT EXISTS %s(%s%s);",
                    table_def.name,
                    column_declarations_cql,
                    primary_key_cql)
    return coordinator:execute(cql, {}, CASSANDRA_EXECUTE_OPTS)
  end


  local function drop_table_if_exists(coordinator, table_name)
    local cql = fmt("DROP TABLE IF EXISTS %s;", table_name)

    return coordinator:execute(cql, {}, CASSANDRA_EXECUTE_OPTS)
  end


  local function get_columns_to_copy(table_structure)
    local res = {}

    for k, _ in pairs(table_structure.columns) do
      res[k] = k
    end

    return res
  end


  local function create_aux_table_def(table_def)
    local aux_table_def = utils.deep_copy(table_def)
    aux_table_def.name = "copy_of_" .. table_def.name
    aux_table_def.columns.partition = "text"

    table.insert(aux_table_def.partition_keys, 1, "partition")

    return aux_table_def
  end


  --[[
    Add a new partition key called "partition" to the table specified by table_def.

    table_def has the following structure:
    { name    = "ssl_certificates",
      columns = {
        id         = "uuid",
        cert       = "text",
        key        = "text",
        created_at = "timestamp",
      },
      partition_keys = { "id" },
    }
  --]]
  function _M.cassandra.add_partition(dao, table_def)
    local copy_records = _M.cassandra.copy_records
    local coordinator, err = dao.db:get_coordinator()
    if not coordinator then
      return nil, err
    end

    table_def = utils.deep_copy(table_def)

    local aux_table_def = create_aux_table_def(table_def)
    local columns_to_copy = get_columns_to_copy(table_def)
    columns_to_copy.partition = function()
      return cassandra.text(table_def.name)
    end

    local _, err = create_table_if_not_exists(coordinator, aux_table_def)
    if err then
      return nil, err
    end

    local _, err = copy_records(dao, table_def, aux_table_def, columns_to_copy)
    if err then
      return nil, err
    end

    local _, err = drop_table_if_exists(coordinator, table_def.name)
    if err then
      return nil, err
    end

    table_def.columns.partition = "text"
    table.insert(table_def.partition_keys, 1, "partition")

    local _, err = create_table_if_not_exists(coordinator, table_def)
    if err then
      return nil, err
    end

    local _, err = copy_records(dao, aux_table_def, table_def, columns_to_copy)
    if err then
      return nil, err
    end

    local _, err = drop_table_if_exists(coordinator, aux_table_def.name)
    if err then
      return nil, err
    end
  end
end
--]==]


return _M
