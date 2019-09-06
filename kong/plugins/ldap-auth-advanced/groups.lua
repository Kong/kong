local utils = require "kong.tools.utils"
local constants = require "kong.constants"
local set_header = kong.service.request.set_header

local split = utils.split
local lower = string.lower

local _M = {}


function _M.set_groups(groups)
  if not groups then
    return
  end

  ngx.ctx.authenticated_groups = groups
  set_header(constants.HEADERS.AUTHENTICATED_GROUPS, table.concat(groups, ", "))
end

-- Ensure that the groups the user is in match the properties that were
-- configured in the plugin
-- @tparam table|string groups - groups returned from ldap search request 
--   e.g. { "CN=test-group-1,CN=Users,DC=addomain,DC=creativehashtags,DC=com",
--          "CN=test-group-2,CN=Users,DC=addomain,DC=creativehashtags,DC=com", }
-- @tparam string gbase_dn - group base dn 
--   e.g. CN=Users,DC=addomain,DC=creativehashtags,DC=com
-- @tparam string gattribute - group name attribute e.g. CN
-- @treturns table|nil - array of groups that pass validation, nil if all invalid
--   e.g. { "test-group-1", "test-group-2", }
function _M.validate_groups(groups, gbase_dn, gattribute)  
  local group_names = {}

  -- coerce groups to array since search returns a string when user belongs
  -- to only one group
  if type(groups) == "string" then
    groups = {groups}
  end

  for _, groupdn in ipairs(groups) do
    local group_match = "^" .. lower(gattribute):gsub("([^%w])", "%%%1") 
                        .. "%=[%w-_+:@]+%,"
                        .. lower(gbase_dn):gsub("([^%w])", "%%%1") .. "$"
    local is_matched = string.match(lower(groupdn), group_match)
                        
    if is_matched and is_matched ~= "" and is_matched ~= gbase_dn then
      -- pick off group name from full dn
      local group_name = split(is_matched, lower(gattribute) .. "=")[2]:sub(1, -2)
      group_names[#group_names + 1] = group_name
    else
      kong.log.debug('"'.. groupdn .. '"' .. ' is not a valid group')
    end
  end
  
  if not group_names[1] then
    return nil
  end
    
  return group_names
end


return _M
