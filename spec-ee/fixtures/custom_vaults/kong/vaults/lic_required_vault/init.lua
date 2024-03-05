-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local http = require "resty.luasocket.http"


local function init()
end


local function get(conf, resource, version)
  local client, err = http.new()
  if not client then
    return nil, err
  end

  client:set_timeouts(20000, 20000, 20000)
  client:request_uri("http://127.0.0.1:" .. conf.port , {
    method = "GET",
    path = "/",
  })

  return resource
end


return {
  VERSION = "1.0.0",
  license_required = true,
  init = init,
  get = get,
}
