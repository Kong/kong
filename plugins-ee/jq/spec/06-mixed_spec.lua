-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

for _, strategy in helpers.all_strategies() do

describe("jq mixed request and response #" .. strategy, function()
  local client

  lazy_setup(function()
    local bp = helpers.get_db_utils(strategy, {
      "routes",
      "services", "plugins",
    }, { "jq" })

    do
      local route = bp.routes:insert({
        hosts = { "test1.example.com" },
      })

      bp.plugins:insert({
        route = { id = route.id },
        name = "jq",
        config = {
          response_jq_program = ".post_data.params",
          request_jq_program = ".[1]",
        },
      })
    end

    assert(helpers.start_kong({
      database = strategy,
      nginx_conf = "spec/fixtures/custom_nginx.template",
      plugins = "jq"
    }))
  end)

  lazy_teardown(function()
    helpers.stop_kong()
  end)

  before_each(function()
    client = helpers.proxy_client()
  end)

  after_each(function()
    if client then
      client:close()
    end
  end)

  it("filters both", function()
    local r = assert(client:send {
      method  = "GET",
      path    = "/request",
      headers = {
        ["Host"] = "test1.example.com",
        ["Content-Type"] = "application/json",
      },
      body = {
        { foo = "bar" },
        { bar = "foo" },
      }
    })

    local json = assert.response(r).has.jsonbody()
    assert.same({ bar = "foo" }, json)
  end)
end)

end
