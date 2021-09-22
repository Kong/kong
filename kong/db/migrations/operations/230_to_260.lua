-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- Helper module for 230_to_260 migration operations.
--
-- Operations are versioned and specific to a migration so they remain
-- fixed in time and are not modified for use in future migrations.
--
-- If you want to reuse these operations in a future migration,
-- copy the functions over to a new versioned module.

local lfs         = require "lfs"
local cassandra   = require "cassandra"
local re_gsub     = ngx.re.gsub
local log         = require "kong.cmd.utils.log"
local enums       = require "kong.enterprise_edition.dao.enums"


local fmt   = string.format

local function cassandra_copy_usernames_to_lower(coordinator, table_name)
  for rows, err in coordinator:iterate("SELECT id, username FROM " .. table_name) do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      if type(row.username) == 'string' then
        local _, err = coordinator:execute("UPDATE " .. table_name .. " SET username_lower = ? WHERE id = ?", {
          cassandra.text(row.username:lower()),
          cassandra.uuid(row.id),
        })
        if err then
          return nil, err
        end
      end
    end
  end

  return true
end

local function output_duplicate_username_lower_report(coordinator, strategy)
  local KONG_PATH = os.getenv("KONG_PATH") or "."
  local outdir = KONG_PATH .. "/migration-reports"
  local outpath = outdir .. "/230_to_260_username_lower_duplicates.csv"
  local unique_username_lowers = {}
  local ws_names = {}

  lfs.mkdir(outdir)

  local outfd = assert(io.open(outpath, "w"))

  outfd:write("id, ws_id, ws_name, type, username, username_lower\n")

  local get_ws_name = function(ws_id)
    if ws_names[ws_id] then
      return ws_names[ws_id]
    end

    local result, err

    if strategy == 'postgres' then
      result, err = coordinator:execute(fmt("SELECT name FROM workspaces WHERE id = '%s'", ws_id))

    elseif strategy == 'cassandra' then
      result, err = coordinator:execute("SELECT name FROM workspaces WHERE id = ?", { cassandra.uuid(ws_id) })

    end

    if result and #result == 1 then
      ws_names[ws_id] = result[1].name
      return ws_names[ws_id]
    end

    return nil, err
  end

  local remove_ws_id = function(str)
    if strategy == 'cassandra' then
      return re_gsub(str, "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:", "")
    else
      return str
    end
  end

  local escape_commas = function(str)
    return re_gsub(str, ",", "\\,")
  end

  local write_duplicate = function(row)
    outfd:write(fmt("%s, %s, %s, %s, %s, %s\n",
      row.id,
      row.ws_id,
      get_ws_name(row.ws_id),
      enums.CONSUMERS.TYPE_LABELS[row.type],
      escape_commas(remove_ws_id(row.username)),
      escape_commas(remove_ws_id(row.username_lower))
    ))
  end

  for rows, err in coordinator:iterate("SELECT id, ws_id, username, username_lower, type FROM consumers") do
    if err then
      return nil, err
    end

    for _, row in ipairs(rows) do
      if type(row.username_lower) == 'string' then
        if type(unique_username_lowers[row.username_lower]) == 'table' then
          write_duplicate(unique_username_lowers[row.username_lower])
          write_duplicate(row)
          unique_username_lowers[row.username_lower] = 2
        elseif type(unique_username_lowers[row.username_lower]) == 'number' then
          write_duplicate(row)
          unique_username_lowers[row.username_lower] = unique_username_lowers[row.username_lower] + 1
        else
          unique_username_lowers[row.username_lower] = row
        end
      end
    end
  end

  outfd:close()

  log("Consumers with duplicate username_lower values output to " .. outpath)

  return true
end

return {
  cassandra_copy_usernames_to_lower = cassandra_copy_usernames_to_lower,
  output_duplicate_username_lower_report = output_duplicate_username_lower_report
}