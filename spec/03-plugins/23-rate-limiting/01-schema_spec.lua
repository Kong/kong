local schema_def = require "kong.plugins.rate-limiting.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: rate-limiting (schema)", function()
  describe("should work when", function()
    it("proper config validates", function()
      local config = { second = 10 }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (bis)", function()
      local config = { second = 10, minute = 20, hour = 30, day = 40, month = 50, year = 60 }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (header)", function()
      local config = { second = 10, limit_by = "header", header_name = "X-App-Version" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (path)", function()
      local config = { second = 10, limit_by = "path", path = "/request" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

  end)

  describe("should fail when", function()
    it("limits: smaller unit is less than bigger unit", function()
      local config = { second = 20, hour = 10 }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("The limit for hour(10.0) cannot be lower than the limit for second(20.0)", err.config)
    end)

    it("limits: smaller unit is less than bigger unit (bis)", function()
      local config = { second = 10, minute = 20, hour = 30, day = 40, month = 60, year = 50 }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("The limit for year(50.0) cannot be lower than the limit for month(60.0)", err.config)
    end)

    it("invalid limit", function()
      local config = {}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.same({"at least one of these fields must be non-empty: 'config.second', 'config.minute', 'config.hour', 'config.day', 'config.month', 'config.year'" },
                  err["@entity"])
    end)

    it("is limited by header but the header_name field is missing", function()
      local config = { second = 10, limit_by = "header", header_name = nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.header_name)
    end)

    it("is limited by path but the path field is missing", function()
      local config = { second = 10, limit_by = "path", path =  nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.path)
    end)

    it("window_type is invalid", function()
      local config = { window_type = "none" }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("expected one of: fixed, sliding", err.config.window_type)
    end)

  end)
end)

describe("Plugin: rate-limiting (schema) - window_type == 'sliding'", function()
  describe("should fail when", function()
    it("is window_type=sliding and policy is not redis", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, policy="local" }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.same({"On redis policy is supported when window_type == 'sliding'" },
      err["@entity"])
    end)

    it("limit is missing", function()
      local config = { window_type = "sliding", window_size = 60}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("required field missing",err.config.limit)
    end)

    it("window_size is missing", function()
      local config = { window_type = "sliding", limit = 10}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("required field missing",err.config.window_size)

    end)

    it("window_size and limit are missing", function()
      local config = { window_type = "sliding" }
      local ok, err = v(config, schema_def)
      local result = {}
      result['limit'] = 'required field missing'
      result['window_size'] = 'required field missing'

      assert.falsy(ok)
      assert.same(result, err.config)
    end)

    it("window_size is less then 0", function()
      local config = { window_type = "sliding", window_size = 0 , limit = 10}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("value must be greater than 0", err.config.window_size)
    end)

    it("limit is less then 0", function()
      local config = { window_type = "sliding", window_size = 60 , limit = -5}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("value must be greater than 0", err.config.limit)
    end)


    it("is limited by header but the header_name field is missing", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, limit_by = "header", header_name = nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.header_name)
    end)

    it("is limited by path but the path field is missing", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, limit_by = "path", path =  nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.path)
    end)
  end)

  describe("should work when", function()
    it("proper config validates window_type == sliding", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, policy = "redis", redis_host = 'localhost' }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (header)", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, policy = "redis", redis_host = 'localhost', limit_by = "header", header_name = "X-App-Version" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (path)", function()
      local config = { window_type = "sliding", window_size = 60 , limit = 10, policy = "redis", redis_host = 'localhost', limit_by = "path", path = "/request" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)
  end)
end)
