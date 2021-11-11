-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

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
