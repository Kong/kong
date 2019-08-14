local http = require("resty.http")

local function http_get(host, port, timeout, path, query)
  local client = http.new()
  client:set_timeout(timeout)

  local ok, err = client:connect(host, port)
  if not ok then
    return ok, err
  end
  local res, err = client:request({
    method = "GET", path = path, query = query
  })

  return res, err
end

return {
  http_get = http_get
}
