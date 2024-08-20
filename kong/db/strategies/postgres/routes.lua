-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local arrays        = require "pgmoon.arrays"
local utils         = require "kong.tools.utils"
local fmt           = string.format
local encode_array  = arrays.encode_array
local table_concat  = table.concat
local table_insert  = table.insert

local Routes = {}


local SQL = [[
  SELECT *
  FROM routes
]]

-- defaults are the values that are equivalent to a DB NULL
local DEFAULTS_METHODS = {"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"}
local DEFAULTS_PATHS = {"/"}


local function append_filter(query, field, values, defaults)
  if values then
    if #query < 2 then
      table_insert(query, " WHERE")

    else
      table_insert(query, " AND")
    end

    -- with params sanitized, we can get an empty array or [[""]=""]
    if #values > 0 then
      local encoded_values = encode_array(values)
      -- when there are values provided, we need to check if
      -- any value of the array overlap with something in the DB
      if defaults then
        -- if the field has defaults (null equivalent), we also need to
        -- check if these values overlap
        table_insert(query, fmt("(%s && %s", field, encoded_values))
        table_insert(query, fmt("OR (%s is NULL AND %s && %s))",
          field, encode_array(defaults), encoded_values))

      else
        table_insert(query, fmt("%s && %s", field, encoded_values))
      end

    else
      if defaults then
        table_insert(query, fmt("(%s is NULL", field))
        table_insert(query, fmt("OR %s && %s)", field, encode_array(defaults)))

      else
        table_insert(query, fmt("%s is NULL", field))
      end
    end
  end
end

function Routes:check_route_overlap(paths, hosts, methods, current_route)
  local query = {SQL}

  append_filter(query, "paths", paths, DEFAULTS_PATHS)
  append_filter(query, "hosts", hosts)
  append_filter(query, "methods", methods, DEFAULTS_METHODS)
  if current_route ~= nil then
    if utils.is_valid_uuid(current_route) then
      table_insert(query, fmt("AND id != %s", self:escape_literal(current_route)))

    else
      table_insert(query, fmt("AND name != %s", self:escape_literal(current_route)))
    end
  end
  table_insert(query, "LIMIT 1;")

  local res, err = self.connector:query(table_concat(query, " "), "read")
  if not res then
    return nil, self.errors:database_error(err)
  end

  if #res > 0 then
    res[1] = self.expand(res[1])
  end

  return res
end


return Routes
