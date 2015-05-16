local cache = require "kong.tools.database_cache"
local stringy = require "stringy"

local _M = {}

function _M.find_api(hosts)
  local api = nil
  for _, host in ipairs(hosts) do
    local sanitized_host = stringy.split(host, ":")[1]
    api = cache.get_and_set(cache.api_key(sanitized_host), function()
      local apis, err = dao.apis:find_by_keys { public_dns = sanitized_host }
      if err then
        return nil, err
      elseif apis and #apis == 1 then
        return apis[1]
      end
    end)
    if api then break end
  end
  return api
end

return _M