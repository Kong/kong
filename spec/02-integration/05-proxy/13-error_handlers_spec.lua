local helpers = require "spec.helpers"


describe("Proxy error handlers", function()
  local proxy_client

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

  it("HTTP 494", function()
    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        ["X-Large"] = string.rep("a", 2^10 * 10), -- default large_client_header_buffers is 8k
      }
    })
    assert.res_status(494, res)
    local body = res:read_body()
    assert.matches("kong/", res.headers.server, nil, true)
    assert.equal("Request Header Or Cookie Too Large\n", body)
  end)

  it("does not expose OpenResty version", function()
    local res = assert(proxy_client:send {
      method = "TRACE",
      path = "/",
    })

    assert.res_status(405, res)
    local body = res:read_body()
    assert.matches("kong/", res.headers.server, nil, true)
    assert.not_matches("openresty/", body, nil, true)
  end)
end)
