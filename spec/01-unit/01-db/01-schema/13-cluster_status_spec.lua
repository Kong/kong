-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require "spec.helpers" -- initializes 'kong' global for plugins
local Entity = require "kong.db.schema.entity"
local clustering_data_planes_schema = require "kong.db.schema.entities.clustering_data_planes"

describe("plugins", function()
  local ClusterDataPlanes
  local validate

  lazy_setup(function()
    ClusterDataPlanes = assert(Entity.new(clustering_data_planes_schema))

    validate = function(b)
      return ClusterDataPlanes:validate(ClusterDataPlanes:process_auto_fields(b, "insert"))
    end
  end)

  it("does not have a cache_key", function()
    assert.is_nil(ClusterDataPlanes.cache_key)
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

  it("rejects incorrect hash length", function()
    local ok, err = validate({ ip = "127.0.0.1", hostname = "dp.example.com", config_hash = "aaa", })
    assert.is_nil(ok)

    assert.equal("length must be 32", err.config_hash)
  end)

  it("rejects incorrect sync status", function()
    local ok, err = validate({ sync_status = "aaa", })
    assert.is_nil(ok)

    assert.matches("expected one of: unknown, normal, kong_version_incompatible, plugin_set_incompatible, plugin_version_incompatible, filter_set_incompatible", err.sync_status)
  end)

  it("accepts correct value", function()
    local ok, err = validate({ ip = "127.0.0.1", hostname = "dp.example.com", })
    assert.is_true(ok)
    assert.is_nil(err)
  end)
end)
