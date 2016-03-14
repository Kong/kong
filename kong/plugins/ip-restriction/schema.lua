local iputils = require "resty.iputils"
local Errors = require "kong.dao.errors"

local function validate_ips(v, t, column)
  local new_fields
  if v and type(v) == "table" then
    for _, ip in ipairs(v) do
      local _, err = iputils.parse_cidr(ip)
      if type(err) == "string" then -- It's an error only if the second variable is a string
        return false, "cannot parse '"..ip.."': "..err
      end
    end
    new_fields = {["_"..column.."_cache"] = iputils.parse_cidrs(v)}
  end
  return true, nil, new_fields
end

return {
  fields = {
    whitelist = {type = "array", func = validate_ips},
    blacklist = {type = "array", func = validate_ips},

    -- Internal use
    _whitelist_cache = {type = "array"},
    _blacklist_cache = {type = "array"}
  },
  self_check = function(schema, plugin_t, dao, is_update)
    local wl = type(plugin_t.whitelist) == "table" and plugin_t.whitelist or {}
    local bl = type(plugin_t.blacklist) == "table" and plugin_t.blacklist or {}

    if #wl > 0 and #bl > 0 then
      return false, Errors.schema "you cannot set both a whitelist and a blacklist"
    elseif #wl == 0 and #bl == 0 then
      return false, Errors.schema "you must set at least a whitelist or blacklist"
    end

    return true
  end
}
