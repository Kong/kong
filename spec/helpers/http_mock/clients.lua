local helpers = require "spec.helpers"
local http_client = helpers.http_client

---@class http_mock
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
