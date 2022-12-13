local redis_storage = require("resty.acme.storage.redis")

local helpers = require "spec.helpers"

describe("Plugin: acme (storage.redis)", function()
  it("should successfully connect to the Redis SSL port", function()
    local config = {
      host = helpers.redis_host,
      port = helpers.redis_ssl_port,
      database = 0,
      auth = nil,
      ssl = true,
      ssl_verify = false,
      ssl_server_name = nil,
    }
    local storage, err = redis_storage.new(config)
    assert.is_nil(err)
    assert.not_nil(storage)
    local err = storage:set("foo", "bar", 10)
    assert.is_nil(err)
    local value, err = storage:get("foo")
    assert.is_nil(err)
    assert.equal("bar", value)
  end)
end)
