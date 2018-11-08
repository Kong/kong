local re_match = ngx.re.match

local bootstrap_server_regex = [[^([^:]+):(\d+)$]]

local _M = {}

--- Parses `host:port` string into a `{host: ..., port: ...}` table.
function _M.bootstrap_server(string)
  local m = re_match(string, bootstrap_server_regex, "jo")
  if not m then
    return nil, "invalid bootstrap server value: " .. string
  end
  return { host = m[1], port = m[2] }
end

return _M
