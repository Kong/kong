local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local pl_tablex = require "pl.tablex"
local groups = require "kong.plugins.acl.groups"

local table_concat = table.concat
local set_header = ngx.req.set_header
local ngx_error = ngx.ERR
local ngx_log = ngx.log
local EMPTY = pl_tablex.readonly {}
local BLACK = "BLACK"
local WHITE = "WHITE"

local mt_cache = { __mode = "k" }
local config_cache = setmetatable({}, mt_cache)



local ACLHandler = BasePlugin:extend()


ACLHandler.PRIORITY = 950
ACLHandler.VERSION = "0.1.1"


function ACLHandler:new()
  ACLHandler.super.new(self, "acl")
end


function ACLHandler:access(conf)
  ACLHandler.super.access(self)

  -- simplify our plugins 'conf' table
  local config = config_cache[conf]
  if not config then
    config = {}
    config.type = (conf.blacklist or EMPTY)[1] and BLACK or WHITE
    config.groups = config.type == BLACK and conf.blacklist or conf.whitelist
    config.cache = setmetatable({}, mt_cache)
    config_cache[conf] = config
  end

  -- get the consumer/credentials
  local consumer_id = groups.get_current_consumer_id()
  if not consumer_id then
    ngx_log(ngx_error, "[acl plugin] Cannot identify the consumer, add an ",
                       "authentication plugin to use the ACL plugin")
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

  -- get the consumer groups, since we need those as cache-keys to make sure
  -- we invalidate properly if they change
  local consumer_groups, err = groups.get_consumer_groups(consumer_id)
  if not consumer_groups then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  -- 'to_be_blocked' is either 'true' if it's to be blocked, or the header
  -- value if it is to be passed
  local to_be_blocked = config.cache[consumer_groups]
  if to_be_blocked == nil then
    local in_group = groups.consumer_in_groups(config.groups, consumer_groups)

    if config.type == BLACK then
      to_be_blocked = in_group
    else
      to_be_blocked = not in_group
    end

    if to_be_blocked == false then
      -- we're allowed, convert 'false' to the header value, if needed
      -- if not needed, set dummy value to save mem for potential long strings
      to_be_blocked = conf.hide_groups_header and "" 
                      or table_concat(consumer_groups, ", ")
    end

    -- update cache
    config.cache[consumer_groups] = to_be_blocked
  end

  if to_be_blocked == true then -- NOTE: we only catch the boolean here!
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

  if not conf.hide_groups_header then
    set_header(constants.HEADERS.CONSUMER_GROUPS, to_be_blocked)
  end
end

return ACLHandler
