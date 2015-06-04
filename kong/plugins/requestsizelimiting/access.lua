local stringy = require "stringy"
local response = require "kong.tools.responses"

local _M = {}


-- Request size limiting, rejects request if payload size is greater than allowed size
--
-- All methods must respect:
-- @param `conf` Configuration table
-- @return `response` contains response code and error message
function _M.execute(conf)
  local headers = ngx.req.get_headers()
  local allowed_bytes_size = conf.allowed_payload_size * 100000
  if tonumber(headers["content-length"]) > allowed_bytes_size then
    if headers.expect and stringy.strip(headers.expect:lower()) == "100-continue" then
      return response.send(417, "Request size limit exceeded")
    else
      return response.send(413, "Request size limit exceeded")
    end
  end
end

return _M
