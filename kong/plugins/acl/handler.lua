local singletons = require "kong.singletons"
local BasePlugin = require "kong.plugins.base_plugin"
local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"
local constants = require "kong.constants"

local table_insert = table.insert
local table_concat = table.concat
local ngx_error = ngx.ERR
local ngx_log = ngx.log
local ipairs = ipairs
local empty = {}

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
  local acls, err = cache.get_or_set(cache.acls_key(consumer_id), nil,
                                load_acls_into_memory, consumer_id)
  if err then
    responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if not acls then
    acls = {}
  end

  local block

  if next(conf.blacklist or empty) and next(acls or empty) then
    for _, v in ipairs(acls) do
      if utils.table_contains(conf.blacklist, v.group) then
        block = true
        break
      end
    end
  end

  if next(conf.whitelist or empty) then
    if not next(acls or empty) then
      block = true
    else
      local contains
      for _, v in ipairs(acls) do
        if utils.table_contains(conf.whitelist, v.group) then
          contains = true
          break
        end
      end
      if not contains then
        block = true
      end
    end
  end

  if block then
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

  -- Prepare header
  local str_acls = {}
  for _, v in ipairs(acls) do
    table_insert(str_acls, v.group)
  end
  ngx.req.set_header(constants.HEADERS.CONSUMER_GROUPS, table_concat(str_acls, ", "))
end

return ACLHandler
