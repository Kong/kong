local responses   = require "kong.tools.responses"
local app_helpers = require "lapis.application"


local _M = {}


function _M.delete_without_sending_response(primary_keys, dao_collection)
  local ok, err = dao_collection:delete(primary_keys)

  if not ok then
    if err then
      return app_helpers.yield_error(err)
    else
      return responses.send_HTTP_NOT_FOUND()
    end
  else
    return nil
  end
end


return _M
