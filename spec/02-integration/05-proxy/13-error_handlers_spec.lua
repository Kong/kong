-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.each_strategy() do
describe("Proxy error handlers", function()
  local proxy_client
  helpers.get_db_utils(strategy, {})

  lazy_setup(function()
    assert(helpers.start_kong {
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })
  end)

  lazy_teardown(function()
    helpers.stop_kong(nil, true)
  end)

  before_each(function()
    proxy_client = helpers.proxy_client()
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end
  end)

  it("HTTP 400", function()
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
      }
    })
    assert.res_status(400, res)
    local body = res:read_body()
    assert.matches("kong/", res.headers.server, nil, true)
    assert.matches("Bad request\nrequest_id: %x+\n", body)
  end)

  it("Request For Routers With Trace Method Not Allowed", function ()
    local res = assert(proxy_client:send {
      method = "TRACE",
      path = "/",
    })
    assert.res_status(405, res)
    local body = res:read_body()
    assert.matches("kong/", res.headers.server, nil, true)
    assert.matches("Method not allowed\nrequest_id: %x+\n", body)
  end)
end)
end
