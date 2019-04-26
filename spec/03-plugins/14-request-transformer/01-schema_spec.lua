local schema_def = require "kong.plugins.request-transformer.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: request-transformer (schema)", function()
  it("validates http_method", function()
    local ok, err = v({ http_method = "GET" }, schema_def)
    assert.truthy(ok)
    assert.falsy(err)
  end)
  it("errors invalid http_method", function()
    local ok, err = v({ http_method = "HELLO!" }, schema_def)
    assert.falsy(ok)
    assert.equal("invalid value: HELLO!", err.config.http_method)
  end)

  describe("remove", function()
    it("accepts remove headers", function()
      local remove_input = {
        headers = {
          "valid"
        }
      }
      local ok, err = v({ remove = remove_input }, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("rejects remove invalid headers", function()
      local remove_input = {
        headers = {
          "%invalid%"
        }
      }
      local ok, err = v({ remove = remove_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.remove.headers[1])
    end)
  end)

  describe("rename", function()
    it("accepts rename headers", function()
      local rename_input = {
        headers = {
          "valid:valid"
        }
      }
      local ok, err = v({ rename = rename_input }, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("rejects rename from valid headers to invalid headers", function()
      local rename_input = {
        headers = {
          "valid:%invalid%"
        }
      }
      local ok, err = v({ rename = rename_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.rename.headers[1])
    end)
    it("rejects rename from invalid headers to valid headers", function()
      local rename_input = {
        headers = {
          "%invalid%:valid"
        }
      }
      local ok, err = v({ rename = rename_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.rename.headers[1])
    end)
    it("rejects rename from invalid headers to invalid headers", function()
      local rename_input = {
        headers = {
          "%invalid%:%invalid%"
        }
      }
      local ok, err = v({ rename = rename_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.rename.headers[1])
    end)
  end)

  describe("replace", function()
    it("accepts replace headers", function()
      local replace_input = {
        headers = {
          "valid:value"
        }
      }
      local ok, err = v({ replace = replace_input }, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("rejects replace invalid headers", function()
      local replace_input = {
        headers = {
          "%invalid%:value"
        }
      }
      local ok, err = v({ replace = replace_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.replace.headers[1])
    end)
  end)

  describe("add", function()
    it("accepts add headers", function()
      local add_input = {
        headers = {
          "valid:value"
        }
      }
      local ok, err = v({ add = add_input }, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("rejects add invalid headers", function()
      local add_input = {
        headers = {
          "%invalid%:value"
        }
      }
      local ok, err = v({ add = add_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.add.headers[1])
    end)
  end)

  describe("append", function()
    it("accepts append headers", function()
      local append_input = {
        headers = {
          "valid:value",
          "valid: value",
          "-_ABCDabcd123456:value"
        }
      }
      local ok, err = v({ append = append_input }, schema_def)
      assert.truthy(ok)
      assert.falsy(err)
    end)
    it("rejects append invalid headers", function()
      local append_input = {
        headers = {
          "%invalid%:value",
          "invalid header:value",
          "'*':value"
        }
      }
      local ok, err = v({ append = append_input }, schema_def)
      assert.falsy(ok)
      assert.equal("'%invalid%' is not a valid header", err.config.append.headers[1])
      assert.equal("'invalid header' is not a valid header", err.config.append.headers[2])
      assert.equal("'\'*\'' is not a valid header", err.config.append.headers[3])
    end)
  end)

end)
