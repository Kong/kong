local log = require "kong.plugins.statsd.log"

describe("Plugin: statsd (log_helper)", function()

  it("should be true with any status code when allow_status_codes is nil", function()
    local allow_status_codes = nil
    assert.is_truthy(log.is_in_range(allow_status_codes, 200))
    assert.is_truthy(log.is_in_range(allow_status_codes, 201))
    assert.is_truthy(log.is_in_range(allow_status_codes, 401))
    assert.is_truthy(log.is_in_range(allow_status_codes, 500))
  end)

  it("should be true when status code is in allowed status code range", function()
    local allow_status_codes = {
      "200-204"
    }

    assert.is_truthy(log.is_in_range(allow_status_codes, 200))
    assert.is_truthy(log.is_in_range(allow_status_codes, 201))
    assert.is_truthy(log.is_in_range(allow_status_codes, 203))
    assert.is_truthy(log.is_in_range(allow_status_codes, 204))
  end)

  it("should be false when status code is not in between two configured ranges", function()
    local allow_status_codes = {
      "200-204",
      "400-404"
    }
    assert.is_false(log.is_in_range(allow_status_codes, 205))
    assert.is_false(log.is_in_range(allow_status_codes, 301))
    assert.is_false(log.is_in_range(allow_status_codes, 500))
  end)
end)

