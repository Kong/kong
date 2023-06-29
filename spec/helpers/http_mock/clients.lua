-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local helpers = require "spec.helpers"
local http_client = helpers.http_client

local http_mock = {}

-- we need to get rid of dependence to the "helpers"
function http_mock:get_client()
  local client = self.client
  if not client then
      client = http_client({
        scheme = self.client_opts.tls and "https" or "http",
        host = "localhost",
        port = self.client_opts.port,
      })

    self.client = client
  end

  return client
end

return http_mock
