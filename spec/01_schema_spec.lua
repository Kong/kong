local validate_entity = require("kong.dao.schemas_validation").validate_entity
local schema          = require "kong.plugins.route-by-header.schema"


describe("route-by-header schema", function()
  it("should allow empty rules list", function()
    local ok, err = validate_entity({}, schema)
    assert.True(ok)
    assert.is_nil(err)
  end)
  it("should allow rule list with one item", function()
    local ok, err = validate_entity({
      rules= {
        {
          condition = {
            header1 =  "value1",
            header2 =  "value2",
          },
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.True(ok)
    assert.is_nil(err)
  end)
  it("should allow rule list with multiple items", function()
    local ok, err = validate_entity({
      rules= {
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
    assert.True(ok)
    assert.is_nil(err)
  end)
  it("should not allow empty condition", function()
    local ok, err = validate_entity({
      rules= {
        {
          condition = {
          },
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.False(ok)
    assert.not_nil(err)
    assert.is_equal(err.rules, "condition must have al-least one entry")
  end)
  it("should not allow rule without condition entry", function()
    local ok, err = validate_entity({
      rules= {
        {
          upstream_name = "bar.domain.com",
        }
      }
    }, schema)
    assert.False(ok)
    assert.not_nil(err)
    assert.is_equal(err.rules, "each rules entry must have an 'upstream_name' and 'condition' defined")
  end)
  it("should not allow empty host", function()
    local ok, err = validate_entity({
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
    assert.False(ok)
    assert.not_nil(err)
    assert.is_equal(err.rules, "each rules entry must have an 'upstream_name' and 'condition' defined")
  end)
  it("should not allow rule without upstream entry", function()
    local ok, err = validate_entity({
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
    assert.False(ok)
    assert.not_nil(err)
    assert.is_equal(err.rules, "each rules entry must have an 'upstream_name' and 'condition' defined")
  end)
end)
