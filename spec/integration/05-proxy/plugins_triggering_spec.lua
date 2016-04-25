local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

describe("Plugins triggering", function()
  setup(function()
    spec_helper.prepare_db()
    spec_helper.insert_fixtures {
      api = {
        {name = "mockbin", request_path = "/mockbin", strip_request_path = true, upstream_url = "http://mockbin.com"}
      },
      consumer = {
        {username = "bob"}
      },
      plugin = {
        {name = "rate-limiting", config = {hour = 1}, __api = 1},
        {name = "rate-limiting", config = {hour = 10}, __api = 1, __consumer = 1}
      }
    }
    spec_helper.start_kong()
  end)

   teardown(function()
    spec_helper.stop_kong()
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
    local url = spec_helper.PROXY_URL.."/mockbin/status/200"

    -- anonymous call
    local _, status, headers = http_client.get(url)
    assert.equal(200, status)
    assert.equal("1", headers["x-ratelimit-limit-hour"])
  end)
end)
