local helpers = require "spec.helpers"
local schema_def = require "kong.plugins.proxy-wasm.schema"


local v = helpers.validate_plugin_config_schema


describe("Plugin: proxy-wasm schema", function()
  describe("accepts", function()
    it("filters without config", function()
      local ok, err = v({
        filters = {
          { name = "auth" },
          { name = "auth" },
        }
      }, schema_def)

      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("filters with config", function()
      local ok, err = v({
        filters = {
          { name = "auth", config = "strategy=x" },
          { name = "auth", config = "strategy=y" },
        }
      }, schema_def)

      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
  end)

  describe("rejects", function()
    it("filters with empty name", function()
      local ok, err = v({
        filters = {
          { name = "" },
        }
      }, schema_def)

      assert.is_falsy(ok)
      assert.same({
        config = {
          filters = {
            { name = "length must be at least 1" },
          }
        }
      }, err)
    end)

    it("filters with empty config", function()
      local ok, err = v({
        filters = {
          { name = "auth", config = "" },
        }
      }, schema_def)

      assert.is_falsy(ok)
      assert.same({
        config = {
          filters = {
            { config = "length must be at least 1" },
          }
        }
      }, err)
    end)

    it("filters with no name", function()
      local ok, err = v({
        filters = {
          {},
        }
      }, schema_def)

      assert.is_falsy(ok)
      assert.same({
        config = {
          filters = {
            { name = "required field missing" },
          }
        }
      }, err)
    end)

    it("when no filters", function()
      local ok, err = v({}, schema_def)

      assert.is_falsy(ok)
      assert.same({
        config = {
          filters = "required field missing",
        }
      }, err)
    end)
  end)
end)

