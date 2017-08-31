local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local pl_tablex = require "pl.tablex"

local table_concat = table.concat
local set_header = ngx.req.set_header
local ngx_error = ngx.ERR
local ngx_log = ngx.log
local EMPTY = pl_tablex.readonly {}
local BLACK = "BLACK"
local WHITE = "WHITE"

local reverse_cache = setmetatable({}, { __mode = "k" })

local new_tab
do
  local ok
  ok, new_tab = pcall(require, "table.new")
  if not ok then
    new_tab = function() return {} end
  end
end


local ACLHandler = BasePlugin:extend()

ACLHandler.PRIORITY = 950

function ACLHandler:new()
  ACLHandler.super.new(self, "acl")
end

local function load_acls_into_memory(consumer_id)
  local results, err = singletons.dao.acls:find_all {consumer_id = consumer_id}
  if err then
    return nil, err
  end
  return results
end

function ACLHandler:access(conf)
  ACLHandler.super.access(self)

  local consumer_id
  local ctx = ngx.ctx

  local authenticated_consumer = ctx.authenticated_consumer
  if authenticated_consumer then
    consumer_id = authenticated_consumer.id
  end

  if not consumer_id then
    local authenticated_credential = ctx.authenticated_credential
    if authenticated_credential then
      consumer_id = authenticated_credential.consumer_id
    end
  end

  if not consumer_id then
    ngx_log(ngx_error, "[acl plugin] Cannot identify the consumer, add an ",
                       "authentication plugin to use the ACL plugin")
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

  -- Retrieve ACL
  local cache_key = singletons.dao.acls:cache_key(consumer_id)
  local acls, err = singletons.cache:get(cache_key, nil,
                                         load_acls_into_memory, consumer_id)
  if err then
    responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if not acls then
    acls = EMPTY
  end

  -- build and cache a reverse-lookup table from our plugins 'conf' table
  local reverse = reverse_cache[conf]
  if not reverse then
    local groups = {}
    reverse = {
      groups = groups,
      type = (conf.blacklist or EMPTY)[1] and BLACK or WHITE,
    }

    -- cache by 'conf', the cache has weak keys, so invalidation of the
    -- plugin 'conf' will also remove it from our local cache here
    reverse_cache[conf] = reverse
    -- build reverse tables for quick lookup
    if reverse.type == BLACK then
      for i = 1, #(conf.blacklist or EMPTY) do
        local groupname = conf.blacklist[i]
        groups[groupname] = groupname
      end

    else
      for i = 1, #(conf.whitelist or EMPTY) do
        local groupname = conf.whitelist[i]
        groups[groupname] = groupname
      end
    end
    -- now create another cache inside this cache for the consumer acls so we
    -- only ever need to evaluate a white/blacklist once.
    -- The key for this cache will be 'acls' which will be invalidated upon
    -- changes. The weak key will make sure our local entry get's GC'ed.
    -- One exception: a blacklist scenario, and a consumer that does
    -- not have any groups. In that case 'acls == EMPTY' so all those users
    -- will be indexed by that table, which is ok, as their result is the
    -- same as well.
    reverse.consumer_access = setmetatable({}, { __mode = "k" })
  end

  -- 'cached_block' is either 'true' if it's to be blocked, or the header
  -- value if it is to be passed
  local cached_block = reverse.consumer_access[acls]
  if not cached_block then
    -- nothing cached, so check our lists and groups
    local block
    if reverse.type == BLACK then
      -- check blacklist
      block = false
      for i = 1, #acls do
        if reverse.groups[acls[i].group] then
          block = true
          break
        end
      end

    else
      -- check whitelist
      block = true
      for i = 1, #acls do
        if reverse.groups[acls[i].group] then
          block = false
          break
        end
      end
    end

    if block then
      cached_block = true

    else
      -- allowed, create the header
      local n = #acls
      local str_acls = new_tab(n, 0)
      for i = 1, n do
        str_acls[i] = acls[i].group
      end
      cached_block = table_concat(str_acls, ", ")
    end

    -- store the result in the cache
    reverse.consumer_access[acls] = cached_block
  end

  if cached_block == true then -- NOTE: we only catch the boolean here!
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

  set_header(constants.HEADERS.CONSUMER_GROUPS, cached_block)
end

return ACLHandler
