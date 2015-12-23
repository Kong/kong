local cache = require "kong.tools.database_cache"
local stringy = require "stringy"

local _M = {}

local function find_api(hosts)
  local retrieved_api, err
  for _, host in ipairs(hosts) do
    local sanitized_host = stringy.split(host, ":")[1]

    retrieved_api, err = cache.get_or_set(cache.api_key(sanitized_host), function()
      local apis, err = dao.apis:find_by_keys {request_host = sanitized_host}
      if err then
        return nil, err
      elseif apis and #apis == 1 then
        return apis[1]
      end
    end)

    if err or retrieved_api then
      return retrieved_api, err
    end
  end
end

function _M.execute()
  local ssl = require "ngx.ssl"
  local server_name = ssl.server_name()
  if server_name then -- Only support SNI requests
    local api, err = find_api({server_name})
    if err then
      ngx.log(ngx.ERR, tostring(err))
    end

    return api
  end
end

return _M
