-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local tablex = require "pl.tablex"
local groups = require "kong.plugins.acl.groups"
local kong_meta = require "kong.meta"
local table_merge = require("kong.tools.table").table_merge


local setmetatable = setmetatable
local concat = table.concat
local error = error
local kong = kong
local get_credential = kong.client.get_credential


local EMPTY = tablex.readonly {}
local DENY = "DENY"
local ALLOW = "ALLOW"


local mt_cache = { __mode = "k" }
local config_cache = setmetatable({}, mt_cache)


local function get_to_be_blocked(config, groups, in_group)
  local to_be_blocked
  if config.type == DENY then
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
ACLHandler.VERSION = kong_meta.core_version


local cache_handle = function(conf)
  local config_type = (conf.deny or EMPTY)[1] and DENY or ALLOW

  local config = {
    hide_groups_header = conf.hide_groups_header,
    type = config_type,
    groups = config_type == DENY and conf.deny or conf.allow,
    cache = setmetatable({}, mt_cache),
  }

  config_cache[conf] = config
  return config
end


function ACLHandler:access(conf)
  -- simplify our plugins 'conf' table
  local config = config_cache[conf]
  if not config then
    cache_handle(conf)
    config = config_cache[conf]
  end

  local to_be_blocked

  -- get the consumer/credentials
  local consumer_id = groups.get_current_consumer_id()
  local credential = get_credential()

  -- when there is no consumer or credential associated with this request
  if not consumer_id then
    -- loads from ngx.authenticated_groups
    local authenticated_groups = groups.get_authenticated_groups(conf.include_consumer_groups)
    if not authenticated_groups then
      -- give more information when authenticated
      if credential then
        return kong.response.error(403, "You cannot consume this service")
      end

      -- Otherwise, just return 401
      return kong.response.error(401)
    end

    -- Check if the authenticated groups match the configured groups
    local in_group = groups.group_in_groups(config.groups, authenticated_groups)
    to_be_blocked = get_to_be_blocked(config, authenticated_groups, in_group)

  -- if there is a consumer
  else
    local authenticated_groups
    -- but no no credential, aka anonymous
    if not credential then
      -- authenticated groups overrides anonymous groups
      authenticated_groups = groups.get_authenticated_groups(conf.include_consumer_groups)
    end

    -- if we have authenticated groups
    if authenticated_groups then
      consumer_id = nil

      local in_group = groups.group_in_groups(config.groups, authenticated_groups)
      to_be_blocked = get_to_be_blocked(config, authenticated_groups, in_group)

      -- if we don't have authenticated groups (and no credentials, aka anonymous)
    else
      -- get the consumer groups, since we need those as cache-keys to make sure
      -- we invalidate properly if they change
      local consumer_groups, err = groups.get_consumer_groups(consumer_id)
      if err then
        return error(err)
      end
      if conf.include_consumer_groups then
        consumer_groups = table_merge(groups.get_authenticated_consumer_groups(), consumer_groups or {})
      end

      -- if we can't find consumer_groups for this consumer
      if not consumer_groups then
        -- when DENY, we set the consumer_groups to an empty table.
        if config.type == DENY then
          consumer_groups = EMPTY

          -- if it's ALLOW, we block the request
        else
          if credential then
            return kong.response.error(403, "You cannot consume this service")
          end

          return kong.response.error(401)
        end
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
    end                         -- if authenticated_groups
  end                           -- if not consumer_id

  if to_be_blocked == true then -- NOTE: we only catch the boolean here!
    return kong.response.error(403, "You cannot consume this service")
  end

  if not conf.hide_groups_header and to_be_blocked then
    kong.service.request.set_header(consumer_id and
                                    constants.HEADERS.CONSUMER_GROUPS or
                                    constants.HEADERS.AUTHENTICATED_GROUPS,
                                    to_be_blocked)
  end
end

return ACLHandler
