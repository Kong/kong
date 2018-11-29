local validate_entity = require("kong.dao.schemas_validation").validate_entity
local canary_schema = require "kong.plugins.canary.schema"


describe("canary schema", function()
  it("should work with all require fields provided", function()
    local ok, err = validate_entity({ percentage = "10", upstream_host = "balancer_a" }, canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time())
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("start in past", function()
    local time =  math.floor(ngx.time()) - 1000
    local ok, err = validate_entity({ start = time,  upstream_host = "balancer_a" },
                                    canary_schema)

    assert.False(ok)
    assert.is_same("'start' cannot be in the past", err.start)
  end)
  it("hash set as `ip`", function()
    local ok, err = validate_entity({ hash = "ip", percentage = "10", upstream_host = "balancer_a" },
      canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("hash set as `none`", function()
    local ok, err = validate_entity({ hash = "none", percentage = "10", upstream_host = "balancer_a" },
      canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("validate duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.False(ok)
    assert.is_same("'duration' must be greater than 0", err.duration)
  end)
  it("validate negative duration ", function()
    local ok, err = validate_entity({ duration = 0,  upstream_host = "balancer_a" },
      canary_schema)

    assert.False(ok)
    assert.is_same("'duration' must be greater than 0", err.duration)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = -1,  upstream_host = "balancer_a" },
      canary_schema)

    assert.False(ok)
    assert.is_same("'percentage' must be in between 0 and 100", err.percentage)
  end)
  it("validate percentage below 0 ", function()
    local ok, err = validate_entity({ percentage = 101,  upstream_host = "balancer_a" },
      canary_schema)

    assert.False(ok)
    assert.is_same("'percentage' must be in between 0 and 100", err.percentage)
  end)
  it("validate upstream_host", function()
    local ok, err = validate_entity({ percentage = "10", upstream_host = "htt://example.com" },
      canary_schema)

    assert.False(ok)
    assert.is_same("'upstream_host' must be a valid hostname", err.upstream_host)
  end)
  it("validate upstream_port", function()
    local ok, err = validate_entity({ percentage = "10", upstream_port = 100 }, canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("validate upstream_port out of range", function()
    local ok, err = validate_entity({ percentage = "10", upstream_port = 100000 }, canary_schema)

    assert.False(ok)
    assert.is_same("'upstream_port' must be a valid portnumber (1 - 65535)", err.upstream_port)
  end)
  it("validate upstream_uri", function()
    local ok, err = validate_entity({ percentage = "10", upstream_uri = "/" }, canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
  it("upstream_host or upstream_uri must be provided", function()
    local ok, _, schema = validate_entity({}, canary_schema)

    assert.False(ok)
    assert.is_same("either 'upstream_uri', 'upstream_host', or 'upstream_port' must be provided",
                   schema.message)
  end)
  it("upstream_fallback requires upstream_host", function()
    local ok, _, schema = validate_entity({upstream_fallback = true, upstream_port = 8080}, canary_schema)

    assert.False(ok)
    assert.is_same("'upstream_fallback' requires 'upstream_host'",
                   schema.message)
  end)
  it("start or percentage must be provided", function()
    local ok, _, schema = validate_entity({ upstream_uri = "/" }, canary_schema)

    assert.False(ok)
    assert.is_same("either 'percentage' or 'start' must be provided",
      schema.message)
  end)
  it("validates what looks like a domain", function()
    local ok, err = validate_entity({ percentage = "10", upstream_host = "balancer_a" }, canary_schema)

    assert.True(ok)
    assert.is_nil(err)
  end)
end)
