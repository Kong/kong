require "spec.helpers" -- initializes 'kong' global for plugins
local Entity = require "kong.db.schema.entity"
local cluster_status_schema = require "kong.db.schema.entities.cluster_status"

describe("plugins", function()
  local ClusterStatus
  local validate

  lazy_setup(function()
    ClusterStatus = assert(Entity.new(cluster_status_schema))

    validate = function(b)
      return ClusterStatus:validate(ClusterStatus:process_auto_fields(b, "insert"))
    end
  end)

  it("does not have a cache_key", function()
    assert.is_nil(ClusterStatus.cache_key)
  end)

  it("checks for required fields", function()
    local ok, err = validate({})
    assert.is_nil(ok)

    assert.equal("required field missing", err.hostname)
    assert.equal("required field missing", err.ip)
  end)

  it("checks for field types", function()
    local ok, err = validate({ ip = "aabbccdd", hostname = "!", })
    assert.is_nil(ok)

    assert.equal("invalid value: !", err.hostname)
    assert.equal("not an ip address: aabbccdd", err.ip)
  end)

  it("accepts correct value", function()
    local ok, err = validate({ ip = "127.0.0.1", hostname = "dp.example.com", })
    assert.is_true(ok)
    assert.is_nil(err)
  end)
end)
