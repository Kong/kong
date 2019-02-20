local log_helper
local statsd

describe("Plugin: statsd-advanced (log_helper)", function()
  setup(function()
    log_helper = require "kong.plugins.statsd-advanced.log_helper"
    statsd = require "kong.vitals.prometheus.statsd.handler"
  end)

  it("should invoke statsd log method with any status code when configuration is empty", function()
    local conf = {}

    stub(statsd, "log")
    log_helper:log(statsd, conf, 200)
    log_helper:log(statsd, conf, 201)
    log_helper:log(statsd, conf, 401)
    log_helper:log(statsd, conf, 500)

    assert.stub(statsd.log).was.called(4)
  end)

  it("should invoke statsd log method when status code is in allowed status code range", function()
    local conf = {
      allow_status_codes = {
          "200-204"
      }
    }

    stub(statsd, "log")
    log_helper:log(statsd, conf, 201)

    assert.stub(statsd.log).was.called(1)
  end)

  it("should invoke statsd log method when status code is exactly the start of the configured range", function()
    local conf = {
      allow_status_codes = {
          "200-204"
      }
    }

    stub(statsd, "log")
    log_helper:log(statsd, conf, 200)

    assert.stub(statsd.log).was.called(1)
  end)

  it("should invoke statsd log method when status code is exactly the end of the configured range", function()
    local conf = {
      allow_status_codes = {
          "200-204"
      }
    }

    stub(statsd, "log")
    log_helper:log(statsd, conf, 204)

    assert.stub(statsd.log).was.called(1)
  end)

  it("should not invoke statsd log method when status code is in between two configured ranges", function()
    local conf = {
      allow_status_codes = {
          "200-204",
          "400-404"
      }
    }

    stub(statsd, "log")
    log_helper:log(statsd, conf, 301)

    assert.stub(statsd.log).was_not.called()
  end)

  it("should not invoke statsd log method when status code is not in allowed status code range", function()
    local conf = {
      allow_status_codes = {
          "200-204"
      }
    }

    stub(statsd, "log")
    log_helper:log(statsd, conf, 205)

    assert.stub(statsd.log).was_not.called()
  end)

  it("should not invoke statsd log method when logger implementation is not provided", function()
    local conf = {
      allow_status_codes = {
        "200-204"
      }
    }

    stub(statsd, "log")
    log_helper:log({}, conf, 205)

    assert.stub(statsd.log).was_not.called()
  end)
end)

