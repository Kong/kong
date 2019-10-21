local cjson = require("cjson")
local http = require("resty.http")

local function http_request(method, uri, data)
  local client = http.new()
  if data then
    return client:request_uri(
      uri,
      {
        method = method,
        body = cjson.encode(data),
        headers = { ["Content-Type"] = "application/json" },
      }
    )
  else
    return client:request_uri(uri, { method = method })
  end
end


return {
  http_request = http_request,
}
