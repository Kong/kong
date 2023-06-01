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

local re_gsub     = ngx.re.gsub
local log         = require "kong.cmd.utils.log"
local enums       = require "kong.enterprise_edition.dao.enums"


local fmt   = string.format

local function escape_commas(str)
  return re_gsub(str, ",", "\\,")
end

local function output_duplicate_username_lower_report(coordinator, strategy)
  local unique_username_lowers = {}
  local conflict_count = 0
  local unique_username_lower_count = 0
  local ws_names = {}

  local get_ws_name = function(ws_id)
    if ws_names[ws_id] then
      return ws_names[ws_id]
    end

    local result, err

    if strategy == 'postgres' then
      result, err = coordinator:query(fmt("SELECT name FROM workspaces WHERE id = '%s'", ws_id))
    end

    if result and #result == 1 then
      ws_names[ws_id] = result[1].name
      return ws_names[ws_id]
    end

    return nil, err
  end

  local remove_ws_id = function(str)
    return str
  end

  local write_duplicate = function(row)
    log(fmt("%s, %s, %s, %s, %s, %s, %s",
      row.id,
      row.ws_id,
      get_ws_name(row.ws_id),
      enums.CONSUMERS.TYPE_LABELS[row.type],
      escape_commas(remove_ws_id(row.username)),
      escape_commas(remove_ws_id(row.username_lower)),
      row.created_at
    ))
  end

  local process_row = function(row)
    if type(row.username_lower) == 'string' then
      local key = fmt("%s:%s", row.ws_id, row.username_lower)

      if type(unique_username_lowers[key]) == 'table' then
        unique_username_lower_count = unique_username_lower_count + 1
        conflict_count = conflict_count + 2

        if unique_username_lower_count == 1 then
          -- first conflict, output message and header
          log([[

The migration to version 2.6 includes a new feature that allows openid-connect
(OIDC) consumer usernames to match an IDP claim case-insensitively. This new
feature is enabled through the openid-connect plugin's config parameter
`by_username_ignore_case`.

If this new feature is used, existing consumers whose username values
case-insensitively match will conflict with each other.  In these cases, the
oldest created_at consumer will be selected for OIDC login.

To avoid having duplicate accounts that can no longer be accessed when enabling
`by_username_ignore_case` for OIDC, you can use this CSV formatted list to
help determine which accounts should be deleted.]]
          )
          log("--------------------------------------------------------------")
          log("id, ws_id, ws_name, type, username, username_lower, created_at")
        end

        write_duplicate(unique_username_lowers[key])
        write_duplicate(row)
        unique_username_lowers[key] = 2

      elseif type(unique_username_lowers[key]) == 'number' then
        conflict_count = conflict_count + 1
        write_duplicate(row)
        unique_username_lowers[key] = unique_username_lowers[key] + 1

      else
        unique_username_lowers[key] = row
      end
    end
  end

  for rows, err in coordinator:iterate("SELECT id, ws_id, username, username_lower, type, created_at FROM consumers") do
    if err then
      return nil, err
    end

    if strategy == 'postgres' then
      process_row(rows)
    end

  end

  if unique_username_lower_count > 0 then
    log("--------------------------------------------------------------")
    log(fmt("Found %s duplicated consumer username_lower values with %s total conflicting consumers (listed above):", unique_username_lower_count, conflict_count))
    for key, value in pairs(unique_username_lowers) do
      if type(value) == 'number' then
        log(fmt("  %s, %s consumers conflict", key, value))
      end
    end
    log("")
  end

  return true
end

return {
  output_duplicate_username_lower_report = output_duplicate_username_lower_report
}
