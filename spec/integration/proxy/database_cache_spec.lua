local spec_helper = require "spec.spec_helpers"
local http_client = require "kong.tools.http_client"

local env = spec_helper.get_env()

describe("Database cache", function()
  local fixtures

  setup(function()
    spec_helper.prepare_db()
    fixtures = spec_helper.insert_fixtures {
      api = {
        {name = "tests-database-cache", request_host = "cache.test", upstream_url = "http://httpbin.org"}
      }
    }

    spec_helper.start_kong()
  end)

  teardown(function()
    spec_helper.stop_kong()
  end)

  it("should expire cache after five seconds", function()
    -- trigger a db fetch for this API's plugins
    http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "cache.test"})

    -- Let's add the authentication plugin configuration
    local _, err = env.dao_factory.plugins:insert {
      name = "key-auth",
      api_id = fixtures.api[1].id,
      config = {
        key_names = {"x-key"}
      }
    }
    assert.falsy(err)

    -- Making the request immediately after will succeed
    local _, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "cache.test"})
    assert.are.equal(200, status)

    -- But waiting after the cache expiration (5 seconds) should block the request
    os.execute("sleep "..tonumber(5))

    local _, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "cache.test"})
    assert.are.equal(401, status)

    -- Create a consumer and a key will make it work again
    local consumer, err = env.dao_factory.consumers:insert {username = "john"}
    assert.falsy(err)

    local _, err = env.dao_factory.keyauth_credentials:insert {
      consumer_id = consumer.id,
      key = "secret_key_123"
    }
    assert.falsy(err)

    -- This should fail, wrong key
    local _, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "cache.test", ["x-key"] = "secret_key"})
    assert.are.equal(403, status)

    -- This should work, right key
    local _, status = http_client.get(spec_helper.PROXY_URL.."/get", {}, {host = "cache.test", ["x-key"] = "secret_key_123"})
    assert.are.equal(200, status)
  end)

end)
