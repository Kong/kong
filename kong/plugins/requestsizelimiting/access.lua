local stringy = require "stringy"
local response = require "kong.tools.responses"

local _M = {}

local CONTENT_LENGTH = "content-length"

local function check_size(length, allowed_size)
  local allowed_bytes_size = allowed_size * 100000
  if length > allowed_bytes_size then
    local headers = ngx.req.get_headers()
    if headers.expect and stringy.strip(headers.expect:lower()) == "100-continue" then
      return response.send(417, "Request size limit exceeded")
    else
      return response.send(413, "Request size limit exceeded")
    end
  end
end

-- Request size limiting, rejects request if payload size is greater than allowed size
--
-- All methods must respect:
-- @param `conf` Configuration table
-- @return `response` contains response code and error message
function _M.execute(conf)
  local headers = ngx.req.get_headers()
  if headers[CONTENT_LENGTH] then
    check_size(tonumber(headers[CONTENT_LENGTH]), conf.allowed_payload_size)
  else
    -- If the request body is too big, this could consume too much memory (to check)
    ngx.req.read_body()
    local data = ngx.req.get_body_data()
    if data then
      check_size(string.len(data), conf.allowed_payload_size)
    end
  end

end

return _M
