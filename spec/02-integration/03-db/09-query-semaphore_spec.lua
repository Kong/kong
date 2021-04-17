-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in pairs({"postgres"}) do


describe( "#".. strategy .. " query locks ", function()
  local client

  setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "plugins",
    }, {
      "slow-query"
    })

    bp.plugins:insert({
      name = "slow-query",
    })

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "slow-query",
      pg_max_concurrent_queries = 1,
      pg_semaphore_timeout = 100,
    }))
    client = helpers.admin_client()
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end)

  it("results in query error failing to acquire resource", function()
    local res = assert(client:send {
      method = "GET",
      path = "/slow-resource?prime=true",
      headers = { ["Content-Type"] = "application/json" }
    })
    assert.res_status(204 , res)

    -- make a request that would run a query while no resources are available
    res = assert(client:send {
      method = "GET",
      path = "/slow-resource",
      headers = { ["Content-Type"] = "application/json" }
    })
    assert.res_status(500 , res)
    -- EE might fail on getting the lock when fetching workspace and
    -- in that case we don't propagate the message
    -- local json = cjson.decode(body)
    -- assert.same({ error = "error acquiring query -- semaphore: timeout" }, json)
  end)
end)

end
