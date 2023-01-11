local log = require "kong.cmd.utils.log"

local assert = assert
local ipairs = ipairs
local migrate_path = require "kong.db.migrations.migrate_path_280_300"


local MAX_ERRORS_TO_REPORT = 10


local validate_atc_expression
do
  local router = require("resty.router.router")
  local CACHED_SCHEMA = require("kong.router.atc").schema
  local get_expression = require("kong.router.compat").get_expression

  local r = router.new(CACHED_SCHEMA)

  validate_atc_expression = function(route)
    local exp = get_expression(route)

    local res, err = r:add_matcher(0, route.id, exp)
    if not res then
      log.error("Regex path may not work with router flavor 'traditional_compatible', " ..
                "route id: %s, err: %s", route.id, err)
      return false
    end

    r:remove_matcher(route.id)

    return true
  end
end


local function c_validate_regex_path(coordinator)
  local validate_ok = true
  local counter = 0

  for rows, err in coordinator:iterate("SELECT id, paths FROM routes") do
    if err then
      return nil, err
    end

    for i = 1, #rows do
      local route = rows[i]

      if not route.paths then
        goto continue
      end

      for idx, path in ipairs(route.paths) do
        local normalized_path, current_changed = migrate_path(path)
        if current_changed then
          route.paths[idx] = normalized_path
        end
      end

      if not validate_atc_expression(route) then
        validate_ok = false
        counter = counter + 1
      end

      if counter >= MAX_ERRORS_TO_REPORT then
        break
      end

      ::continue::
    end
  end

  if not validate_ok then
    return nil, "Regex path validatioin failed."
  end

  return true
end


local function p_validate_regex_path(connector)
  local validate_ok = true
  local counter = 0

  for route, err in connector:iterate("SELECT id, paths FROM routes WHERE paths IS NOT NULL") do
    if err then
      return nil, err
    end

    for idx, path in ipairs(route.paths) do
      local normalized_path, current_changed = migrate_path(path)
      if current_changed then
        route.paths[idx] = normalized_path
      end
    end

    if not validate_atc_expression(route) then
      validate_ok = false
      counter = counter + 1
    end

    if counter >= MAX_ERRORS_TO_REPORT then
      break
    end
  end

  if not validate_ok then
    return nil, "Regex path validatioin failed."
  end

  return true
end


return {
  postgres = p_validate_regex_path,

  cassandra = function(connector)
    local coordinator = assert(connector:get_stored_connection())
    local _, err = c_validate_regex_path(coordinator)
    if err then
      return nil, err
    end
  end,
}
