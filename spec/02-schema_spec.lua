local schemas = require "kong.dao.schemas_validation"
local statsd_schema = require "kong.plugins.statsd-advanced.schema"
local validate_entity = schemas.validate_entity

describe("Plugin: statsd-advanced (schema)", function()
  it("accepts empty config", function()
    local ok, err = validate_entity({}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("accepts empty metrics", function()
    local metrics_input = {}
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("accepts just one metrics", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
        sample_rate = 1
      }
    }
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("rejects if name or stat not defined", function()
    local metrics_input = {
      {
        name = "request_count",
        sample_rate = 1
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("name and stat_type must be defined for all stats", err.metrics)
    local metrics_input = {
      {
        stat_type = "counter",
        sample_rate = 1
      }
    }
    _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("name and stat_type must be defined for all stats", err.metrics)
  end)
  it("rejects counters without sample rate", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
  end)
  it("rejects invalid metrics name", function()
    local metrics_input = {
      {
        name = "invalid_name",
        stat_type = "counter",
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("unrecognized metric name: invalid_name", err.metrics)
  end)
  it("rejects invalid stat type", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "invalid_stat",
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("unrecognized stat_type: invalid_stat", err.metrics)
  end)
  it("rejects if customer identifier missing", function()
    local metrics_input = {
      {
        name = "status_count_per_user",
        stat_type = "counter",
        sample_rate = 1
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("consumer_identifier must be defined for metric status_count_per_user", err.metrics)
  end)
  it("rejects invalid service identifier", function()
    local metrics_input = {
      {
        name = "status_count",
        stat_type = "counter",
        sample_rate = 1,
        service_identifier = "fooo",
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("invalid service_identifier for metric 'status_count'. " .. 
                 "Choices are service_id, service_name, service_host and service_name_or_host", err.metrics)
  end)
  it("accepts empty service identifier", function()
    local metrics_input = {
      {
        name = "status_count",
        stat_type = "counter",
        sample_rate = 1,
      }
    }
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("accepts valid service identifier", function()
    local metrics_input = {
      {
        name = "status_count",
        stat_type = "counter",
        sample_rate = 1,
        service_identifier = "service_id",
      }
    }
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("rejects invalid workspace identifier", function()
    local metrics_input = {
      {
        name = "status_count_per_workspace",
        stat_type = "counter",
        sample_rate = 1,
        workspace_identifier = "fooo",
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("invalid workspace_identifier for metric 'status_count_per_workspace'. "..
                 "Choices are workspace_id and workspace_name", err.metrics)
  end)
  it("rejects empty workspace identifier", function()
    local metrics_input = {
      {
        name = "status_count_per_workspace",
        stat_type = "counter",
        sample_rate = 1,
      }
    }
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("workspace_identifier must be defined for metric status_count_per_workspace", err.metrics)
  end)
  it("accepts valid workspace identifier", function()
    local metrics_input = {
      {
        name = "status_count_per_workspace",
        stat_type = "counter",
        sample_rate = 1,
        workspace_identifier = "workspace_id",
      }
    }
    local ok, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.is_nil(err)
    assert.is_true(ok)
  end)
  it("rejects if metric has wrong stat type", function()
    local metrics_input = {
      {
        name = "unique_users",
        stat_type = "counter"
      }
    }
    local _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("unique_users metric only works with stat_type 'set'", err.metrics)
    metrics_input = {
      {
        name = "status_count",
        stat_type = "set",
        sample_rate = 1
      }
    }
    _, err = validate_entity({ metrics = metrics_input}, statsd_schema)
    assert.not_nil(err)
    assert.equal("status_count metric only works with stat_type 'counter'", err.metrics)
  end)
end)
