local PLUGIN_NAME = "statsd"

-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()
  local snapshot

  setup(function()
    snapshot = assert:snapshot()
    assert:set_parameter("TableFormatLevel", -1)
  end)

  teardown(function()
    snapshot:revert()
  end)


  it("accepts empty config", function()
    local ok, err = validate({})
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("accepts empty metrics", function()
    local metrics_input = {}
    local ok, err = validate({ metrics = metrics_input})
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)


  it("accepts just one metrics", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
        sample_rate = 1
      }
    }
    local ok, err = validate({ metrics = metrics_input})
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
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            stat_type = 'field required for entity check'
          }
        }
      }
    }, err)

    local metrics_input = {
      {
        stat_type = "counter",
        sample_rate = 1
      }
    }
    _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            name = 'field required for entity check'
          }
        }
      }
    }, err)
  end)


  it("rejects counters without sample rate", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "counter",
      }
    }
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            ["@entity"] = {
              [1] = "failed conditional validation given value of field 'stat_type'"
            },
            sample_rate = 'required field missing'
          }
        }
      }
    }, err)
  end)


  it("rejects invalid metrics name", function()
    local metrics_input = {
      {
        name = "invalid_name",
        stat_type = "counter",
        sample_rate = 1,
      }
    }
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            name = 'expected one of: kong_latency, latency, request_count, request_per_user, request_size, response_size, status_count, status_count_per_user, unique_users, upstream_latency'
          }
        }
      }
    }, err)
  end)


  it("rejects invalid stat type", function()
    local metrics_input = {
      {
        name = "request_count",
        stat_type = "invalid_stat",
      }
    }
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            stat_type = 'expected one of: counter, gauge, histogram, meter, set, timer'
          }
        }
      }
    }, err)
  end)


  it("rejects if consumer identifier missing", function()
    local metrics_input = {
      {
        name = "status_count_per_user",
        stat_type = "counter",
        sample_rate = 1
      }
    }
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            ["@entity"] = {
              [1] = "failed conditional validation given value of field 'name'"
            },
            consumer_identifier = 'required field missing'
          }
        }
      }
    }, err)
  end)


  it("rejects if metric has wrong stat type", function()
    local metrics_input = {
      {
        name = "unique_users",
        stat_type = "counter"
      }
    }
    local _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            ["@entity"] = {
              [1] = "failed conditional validation given value of field 'name'",
              [2] = "failed conditional validation given value of field 'stat_type'",
              [3] = "failed conditional validation given value of field 'name'"
            },
            consumer_identifier = 'required field missing',
            sample_rate = 'required field missing',
            stat_type = 'value must be set'
          }
        }
      }
    }, err)

    metrics_input = {
      {
        name = "status_count",
        stat_type = "set",
        sample_rate = 1
      }
    }
    _, err = validate({ metrics = metrics_input})
    assert.same({
      config = {
        metrics = {
          [1] = {
            ["@entity"] = {
              [1] = "failed conditional validation given value of field 'name'"
            },
            stat_type = 'value must be counter'
          }
        }
      }
    }, err)
  end)
end)
