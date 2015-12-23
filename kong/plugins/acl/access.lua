local cache = require "kong.tools.database_cache"
local responses = require "kong.tools.responses"
local utils = require "kong.tools.utils"

local _M = {}

function _M.execute(conf)
  local consumer_id
  if ngx.ctx.authenticated_credential then
    consumer_id = ngx.ctx.authenticated_credential.consumer_id
  else
    return responses.send_HTTP_FORBIDDEN("Cannot identify the consumer, add an authentication plugin to use the ACL plugin")
  end

  -- Retrieve ACL
  local acls = cache.get_or_set(cache.acls_key(consumer_id), function()
    local results, err = dao.acls:find_by_keys({consumer_id = consumer_id})
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end
    return results
  end)

  if not acls then acls = {} end

  local block

  if utils.table_size(conf.blacklist) > 0 and utils.table_size(acls) > 0 then
    for _, v in ipairs(acls) do
      if utils.table_contains(conf.blacklist, v.group) then
        block = true
        break
      end
    end
  end

  if utils.table_size(conf.whitelist) > 0 then
    if utils.table_size(acls) == 0 then
      block = true
    else
      local contains
      for _, v in ipairs(acls) do
        if utils.table_contains(conf.whitelist, v.group) then
          contains = true
          break
        end
      end
      if not contains then block = true end
    end
  end

  if block then
    return responses.send_HTTP_FORBIDDEN("You cannot consume this service")
  end

end

return _M
