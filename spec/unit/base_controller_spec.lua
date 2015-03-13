local base_controller = require "kong.web.routes.base_controller"
local spec_helper = require "spec.spec_helpers"

describe("Base Controller", function()

  it("should not parse params with empty values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, nil)
    assert.are.same({}, result)
  end)

  it("should not parse params with empty values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, {})
    assert.are.same({}, result)
  end)

  it("should not parse params with invalid values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, {hello = true})
    assert.are.same({}, result)
  end)

  it("should not parse params with invalid schema", function()
    local result = base_controller.parse_params({}, {hello = true})
    assert.are.same({}, result)
  end)

  it("should not parse params with nil schema", function()
    local result = base_controller.parse_params(nil, {hello = true})
    assert.are.same({}, result)
  end)

  it("should not parse params with empty values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, {})
    assert.are.same({}, result)
  end)

  it("should not parse params with invalid values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, {hello = true, wot = 123})
    assert.are.same({}, result)
  end)

  it("should parse only existing params", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.accounts._schema, {hello = true, provider_id = 123})
    assert.are.same({
      provider_id = 123
    }, result)
  end)

  it("should parse tables without invalid sub-schema values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {name = "wot", authentication_type = "query" })
    assert.are.same({
      name = "wot",
      value = {}
    }, result)

    result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {name = "authentication", wot = "query" })
    assert.are.same({
      name = "authentication",
      value = {}
    }, result)
  end)

  it("should parse tables with valid sub-schema values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {name = "authentication", authentication_type = "query" })
    assert.are.same({
      name = "authentication",
      value = {
        authentication_type = "query"
      }
    }, result)
  end)

  it("should parse tables with skippig invalid values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {name = "authentication", authentication_type = "query", wot = "ciao" })
    assert.are.same({
      name = "authentication",
      value = {
        authentication_type = "query"
      }
    }, result)
  end)

  it("should parse reversed-order tables with valid sub-schema values", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {authentication_type = "query", name = "authentication" })
    assert.are.same({
      name = "authentication",
      value = {
        authentication_type = "query"
      }
    }, result)
  end)

  it("should parse arrays with a correct delimitator", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {authentication_type = "query", name = "authentication", authentication_key_names = "wot,wat" })
    assert.are.same({
      name = "authentication",
      value = {
        authentication_type = "query",
        authentication_key_names = { "wot", "wat" }
      }
    }, result)
  end)

  it("should parse arrays with a incorrect delimitator", function()
    local result = base_controller.parse_params(spec_helper.dao_factory.plugins._schema, {authentication_type = "query", name = "authentication", authentication_key_names = "wot;wat" })
    assert.are.same({
      name = "authentication",
      value = {
        authentication_type = "query",
        authentication_key_names = { "wot;wat" }
      }
    }, result)
  end)

end)