local helpers = require "spec.helpers"

describe("origins config option", function()
  local proxy_client
  local bp

  before_each(function()
    bp = helpers.get_db_utils(nil, {
      "routes",
      "services",
    })
  end)

  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()
  end)

  it("respects origins for overriding resolution", function()
    local service = bp.services:insert({
      protocol = helpers.mock_upstream_protocol,
      host     = helpers.mock_upstream_host,
      port     = 1, -- wrong port
    })
    bp.routes:insert({
      service = service,
      hosts = { "mock_upstream" }
    })

    -- Check that error occurs trying to talk to port 1
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()
    local res = proxy_client:get("/request", {
      headers = { Host = "mock_upstream" }
    })
    assert.res_status(502, res)
    proxy_client:close()
    helpers.stop_kong(nil, nil, true)

    -- Now restart with origins option
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      origins = string.format("%s://%s:%d=%s://%s:%d",
        helpers.mock_upstream_protocol,
        helpers.mock_upstream_host,
        1,
        helpers.mock_upstream_protocol,
        helpers.mock_upstream_host,
        helpers.mock_upstream_port),
    }))

    proxy_client = helpers.proxy_client()
    local res = proxy_client:get("/request", {
      headers = { Host = "mock_upstream" }
    })
    assert.res_status(200, res)
  end)
end)
