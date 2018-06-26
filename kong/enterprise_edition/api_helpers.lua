local constants = require "kong.constants"


local _M = {}


function _M.get_consumer_id_from_headers()
  return ngx.req.get_headers()[constants.HEADERS.CONSUMER_ID]
end


return _M
