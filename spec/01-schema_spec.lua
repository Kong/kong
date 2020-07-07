local validate_entity = require("spec.helpers").validate_plugin_config_schema
local canary_schema = require "kong.plugins.canary.schema"


describe("canary schema", function()
  it("should work with all require fields provided", function()
    local ok, err = validate_entity({ percentage = 10, upstream_host = "balancer_a" }, canary_schema)
 
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time())
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time()) - 1000
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.is_falsy(ok)
    assert.is_same("'start' cannot be in the past", err.config.start)
  end)
  it("hash set as `ip`", function()
    local ok, err = validate_entity({ hash = "ip", percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("hash set as `none`", function()
    local ok, err = validate_entity({ hash = "none", percentage = 10, upstream_host = "balancer_a" },
      canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("validate duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value must be greater than 0", err.config.duration)
  end)
  it("validate negative duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value must be greater than 0", err.config.duration)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = -1,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 100", err.config.percentage)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = 101,  upstream_host = "balancer_a" },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 100", err.config.percentage)
  end)
  it("validate upstream_host", function()
    local upstream_host = "htt://example.com";
    local ok, err = validate_entity({ percentage = "10", upstream_host = upstream_host },
      canary_schema)

    assert.is_falsy(ok)
    assert.is_same("invalid value: " .. upstream_host, err.config.upstream_host)
  end)
  it("validate upstream_port", function()
    local ok, err = validate_entity({ percentage = 10, upstream_port = 100 }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("validate upstream_port out of range", function()
    local ok, err = validate_entity({ percentage = 10, upstream_port = 100000 }, canary_schema)

    assert.is_falsy(ok)
    assert.is_same("value should be between 0 and 65535", err.config.upstream_port)
  end)
  it("validate upstream_uri", function()
    local ok, err = validate_entity({ percentage = 10, upstream_uri = "/" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("upstream_host or upstream_uri must be provided", function()
    local ok, err = validate_entity({}, canary_schema)

    assert.is_falsy(ok)
    local expected = {
      "at least one of these fields must be non-empty: 'config.upstream_uri', 'config.upstream_host', 'config.upstream_port'",
      "at least one of these fields must be non-empty: 'config.percentage', 'config.start'"
    }
    assert.is_same(expected, err["@entity"])
  end)
  it("upstream_fallback requires upstream_host", function()
    local ok, err = validate_entity({upstream_fallback = true, upstream_port = 8080}, canary_schema)

    assert.is_falsy(ok)
    local expected = {
      "failed conditional validation given value of field 'config.upstream_fallback'",
      "at least one of these fields must be non-empty: 'config.percentage', 'config.start'"
    }
    assert.is_same(expected, err["@entity"])
  end)
  it("start or percentage must be provided", function()
    local ok, err = validate_entity({ upstream_uri = "/" }, canary_schema)

    assert.is_falsy(ok)
    local expected = {
      "at least one of these fields must be non-empty: 'config.percentage', 'config.start'"
    }
    assert.is_same(expected, err["@entity"])
  end)
  it("validates what looks like a domain", function()
    local ok, err = validate_entity({ percentage = 10, upstream_host = "balancer_a" }, canary_schema)

    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
end)
