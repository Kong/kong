--- part of http_mock
-- @submodule spec.helpers.http_mock

local helpers = require "spec.helpers"
local http_client = helpers.http_client

local http_mock = {}

--- get a `helpers.http_client` to access the mock server
-- @function http_mock:get_client
-- @treturn http_client a `helpers.http_client` instance
-- @within http_mock
-- @usage
-- httpc = http_mock:get_client()
-- result = httpc:get("/services/foo", opts)
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
