local constants = require "kong.constants"
local tablex = require "pl.tablex"
local groups = require "kong.plugins.acl.groups"


local setmetatable = setmetatable
local concat = table.concat
local kong = kong


local EMPTY = tablex.readonly {}
local BLACK = "BLACK"
local WHITE = "WHITE"


local mt_cache = { __mode = "k" }
local config_cache = setmetatable({}, mt_cache)


local function get_to_be_blocked(config, groups, in_group)
  local to_be_blocked
  if config.type == BLACK then
    to_be_blocked = in_group
  else
    to_be_blocked = not in_group
  end

  if to_be_blocked == false then
    -- we're allowed, convert 'false' to the header value, if needed
    -- if not needed, set dummy value to save mem for potential long strings
    to_be_blocked = config.hide_groups_header and "" or concat(groups, ", ")
  end

  return to_be_blocked
end


local ACLHandler = {}


ACLHandler.PRIORITY = 950
ACLHandler.VERSION = "2.1.0"


function ACLHandler:access(conf)
  -- simplify our plugins 'conf' table
  local config = config_cache[conf]
  if not config then
    local config_type = (conf.blacklist or EMPTY)[1] and BLACK or WHITE

    config = {
      hide_groups_header = conf.hide_groups_header,
      type = config_type,
      groups = config_type == BLACK and conf.blacklist or conf.whitelist,
      cache = setmetatable({}, mt_cache),
    }

    config_cache[conf] = config
  end

  local to_be_blocked

  -- get the consumer/credentials
  local consumer_id = groups.get_current_consumer_id()
  if not consumer_id then
    local authenticated_groups = groups.get_authenticated_groups()
    if not authenticated_groups then
      kong.log.err("Cannot identify the consumer, add an authentication ",
                   "plugin to use the ACL plugin")

      return kong.response.exit(403, {
        message = "You cannot consume this service"
      })
    end

    local in_group = groups.group_in_groups(config.groups, authenticated_groups)
    to_be_blocked = get_to_be_blocked(config, authenticated_groups, in_group)

  else
    local authenticated_groups
    if not kong.client.get_credential() then
      -- authenticated groups overrides anonymous groups
      authenticated_groups = groups.get_authenticated_groups()
    end

    if authenticated_groups then
      consumer_id = nil

      local in_group = groups.group_in_groups(config.groups, authenticated_groups)
      to_be_blocked = get_to_be_blocked(config, authenticated_groups, in_group)

    else
      -- get the consumer groups, since we need those as cache-keys to make sure
      -- we invalidate properly if they change
      local consumer_groups, err = groups.get_consumer_groups(consumer_id)
      if not consumer_groups then
        kong.log.err(err)
        return kong.response.exit(500, {
          message = "An unexpected error occurred"
        })
      end

      -- 'to_be_blocked' is either 'true' if it's to be blocked, or the header
      -- value if it is to be passed
      to_be_blocked = config.cache[consumer_groups]
      if to_be_blocked == nil then
        local in_group = groups.consumer_in_groups(config.groups, consumer_groups)
        to_be_blocked = get_to_be_blocked(config, consumer_groups, in_group)

        -- update cache
        config.cache[consumer_groups] = to_be_blocked
      end
    end
  end

  if to_be_blocked == true then -- NOTE: we only catch the boolean here!
    return kong.response.exit(403, {
      message = "You cannot consume this service"
    })
  end

  if not conf.hide_groups_header and to_be_blocked then
    kong.service.request.set_header(consumer_id and
                                    constants.HEADERS.CONSUMER_GROUPS or
                                    constants.HEADERS.AUTHENTICATED_GROUPS,
                                    to_be_blocked)
  end
end


return ACLHandler
