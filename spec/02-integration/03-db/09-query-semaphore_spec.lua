local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("Postgres query locks", function()
  local client

  setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "plugins",
    }, {
      "slow-query"
    })

    bp.plugins:insert({
      name = "slow-query",
    })

    assert(helpers.start_kong({
      database = "postgres",
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
    local body = assert.res_status(500 , res)
    local json = cjson.decode(body)
    assert.same({ error = "error acquiring query semaphore: timeout" }, json)
  end)
end)
