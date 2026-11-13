local _M = {}

local check_hostname = require("kong.tools.ip").check_hostname

function _M.is_valid_hostname(hostname)
  if hostname == nil or hostname == "" then
    return false
  end
  return check_hostname(hostname) ~= nil
end

return _M
