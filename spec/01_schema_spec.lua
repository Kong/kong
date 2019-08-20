local v = require("spec.helpers").validate_plugin_config_schema
local schema          = require "kong.plugins.route-by-header.schema"


describe("route-by-header schema", function()
  it("should allow empty rules list", function()
    local ok, err = v({}, schema)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("should allow rule list with one item", function()
    local ok, err = v({
      rules = {
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
          },
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)
  it("should allow rule list with multiple items", function()
    local ok, err = v({
      rules = {
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
          },
          upstream_name = "bar.domain.com",
        },
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
            header3 =  "value3",
          },
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.truthy(ok)
    assert.is_nil(err)
  end)
  it("should not allow empty condition", function()
    local ok, err = v({
      rules= {
        {
          condition = {},
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.falsy(ok)
    assert.not_nil(err)
    assert.equal(err.config.rules[1].condition, "length must be at least 1")
  end)
  it("should not allow rule without condition entry", function()
    local ok, err = v({
      rules= {
        {
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.falsy(ok)
    assert.not_nil(err)
    assert.is_equal(err.config.rules[1].condition, "required field missing")
  end)
  it("should not allow empty host", function()
    local ok, err = v({
      rules= {
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
            header3 =  "value3",
          },
          upstream_name = "",
        }
      }
    }, schema)
    assert.falsy(ok)
    assert.not_nil(err)
    assert.is_equal(err.config.rules[1].upstream_name, "length must be at least 1")
  end)
  it("should not allow rule without upstream entry", function()
    local ok, err = v({
      rules= {
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
            header3 =  "value3",
          },
        }
      }
    }, schema)
    assert.falsy(ok)
    assert.not_nil(err)
    assert.is_equal(err.config.rules[1].upstream_name, "required field missing")
  end)
end)
