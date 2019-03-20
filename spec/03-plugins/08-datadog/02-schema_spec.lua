local schema_def = require "kong.plugins.datadog.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: datadog (schema)", function()
  it("accepts empty config", function()
    local ok, err = v({}, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
  it("accepts empty metrics", function()
    local metrics_input = {}
    local ok, err = v({ metrics = metrics_input }, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
  it("accepts just one metrics", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
        sample_rate = 1,
        tags = {"K1:V1"}
      }
    }
    local ok, err = v({ metrics = metrics_input }, schema_def)
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)
  it("rejects if name or stat not defined", function()
    local metrics_input = {
      {
        name = "request_count",
        sample_rate = 1
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.same({ stat_type = "field required for entity check" }, err.config.metrics)
    local metrics_input = {
      {
        stat_type = "counter",
        sample_rate = 1
      }
    }
    _, err = v({ metrics = metrics_input }, schema_def)
    assert.same("field required for entity check", err.config.metrics.name)
  end)
  it("rejects counters without sample rate", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.not_nil(err)
  end)
  it("rejects invalid metrics name", function()
    local metrics_input = {
      {
        name = "invalid_name",
        stat_type = "counter",
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.match("expected one of: kong_latency", err.config.metrics.name)
    assert.equal("required field missing", err.config.metrics.sample_rate)
  end)
  it("rejects invalid stat type", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "invalid_stat",
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.match("expected one of: counter", err.config.metrics.stat_type)
  end)
  it("rejects if customer identifier missing", function()
    local metrics_input = {
      {
        name = "status_count_per_user",
        stat_type = "counter",
        sample_rate = 1
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.equals("required field missing", err.config.metrics.kongsumer_identifier)
  end)
  it("rejects if metric has wrong stat type", function()
    local metrics_input = {
      {
        name = "unique_users",
        stat_type = "counter"
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.not_nil(err)
    assert.equal("value must be set", err.config.metrics.stat_type)
    metrics_input = {
      {
        name = "status_count",
        stat_type = "set",
        sample_rate = 1
      }
    }
    _, err = v({ metrics = metrics_input }, schema_def)
    assert.not_nil(err)
    assert.equal("value must be counter", err.config.metrics.stat_type)
  end)
  it("rejects if tags malformed", function()
    local metrics_input = {
      {
        name = "status_count",
        stat_type = "counter",
        sample_rate = 1,
        tags = {"T1:"}
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.same({ tags = "invalid value: T1:" }, err.config.metrics)
  end)
  it("accept if tags is aempty list", function()
    local metrics_input = {
      {
        name = "status_count",
        stat_type = "counter",
        sample_rate = 1,
        tags = {}
      }
    }
    local _, err = v({ metrics = metrics_input }, schema_def)
    assert.is_nil(err)
  end)
end)
