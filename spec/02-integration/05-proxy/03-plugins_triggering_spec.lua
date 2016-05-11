local helpers = require "spec.helpers"

describe("Plugins triggering", function()
  local client
  setup(function()
    helpers.dao:truncate_tables()

    local consumer = assert(helpers.dao.consumers:insert {
      username = "bob"
    })
    local api = assert(helpers.dao.apis:insert {
      name = "mockbin",
      request_path = "/mockbin",
      strip_request_path = true,
      upstream_url = "http://mockbin.com"
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api.id,
      config = {
        hour = 1,
      }
    })
    assert(helpers.dao.plugins:insert {
      name = "rate-limiting",
      api_id = api.id,
      consumer_id = consumer.id,
      config = {
        hour = 1,
      }
    })

    assert(helpers.prepare_prefix())
    assert(helpers.start_kong())
    client = assert(helpers.http_client("127.0.0.1", helpers.proxy_port))
  end)

  teardown(function()
    if client then
      client:close()
    end
    helpers.stop_kong()
  end)

  -- here have 2 rows in our plugins table, one with a
  -- consumer_id column, the other without.
  -- With Cassandra, it is not possible to have a WHERE clause
  -- targetting specifically the null consumer_id row. Hence,
  -- depending on Cassandra storage internals, the plugin iterator could
  -- return the row that applies to a consumer, or the one that does
  -- not, making this behavior non-deterministic.
  -- the previous **hack** was to have a "nullified" uuid (0000s),
  -- but since Postgres support, this hack has been removed. Instead,
  -- the plugin iterator now manually filters the rows returned :(
  -- this hack will only be used when Cassandra is our backend.
  it("applies the correct plugin for a consumer", function()
    local res = assert(client:send {
      method = "GET",
      path = "/mockbin/status/200"
    })
    assert.res_status(200, res)
    assert.equal("1", res.headers["x-ratelimit-limit-hour"])
  end)
end)
