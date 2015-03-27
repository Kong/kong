local base_controller = require "kong.web.routes.base_controller"
local spec_helper = require "spec.spec_helpers"

local env = spec_helper.get_env()

describe("Base Controller", function()

  it("should not parse params with empty values", function()
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, nil)
    assert.are.same({}, result)
  end)

  it("should not parse params with empty values", function()
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, {})
    assert.are.same({}, result)
  end)

  it("should not parse params with invalid values", function()
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, {hello = true})
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
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, {})
    assert.are.same({}, result)
  end)

  it("should not parse params with invalid values", function()
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, {hello = true, wot = 123})
    assert.are.same({}, result)
  end)

  it("should parse only existing params", function()
    local result = base_controller.parse_params(env.dao_factory.consumers._schema, {hello = true, custom_id = 123})
    assert.are.same({
      custom_id = 123
    }, result)
  end)

  it("should parse tables without invalid sub-schema values", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "wot", ["value.key_names"] = "apikey" })
    assert.are.same({
      name = "wot",
      value = {}
    }, result)

    result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "keyauth", wot = "query" })
    assert.are.same({
      name = "keyauth",
      value = {}
    }, result)
  end)
  it("should parse tables with valid sub-schema values", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "keyauth", ["value.key_names"] = "apikey" })
    assert.are.same({
      name = "keyauth",
      value = {
        key_names = { "apikey" }
      }
    }, result)
  end)
  it("should not parse tables with invalid subschema prefix", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "keyauth", ["asd.key_names"] = "apikey" })
    assert.are.same({
      name = "keyauth",
      value = {}
    }, result)

    result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "keyauth", ["key_names"] = "apikey" })
    assert.are.same({
      name = "keyauth",
      value = {}
    }, result)
  end)

  it("should parse tables with skippig invalid values", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {name = "keyauth", ["value.key_names"] = "apikey", ["value.wot"] = "ciao" })
    assert.are.same({
      name = "keyauth",
      value = {
        key_names = { "apikey" }
      }
    }, result)
  end)

  it("should parse reversed-order tables with valid sub-schema values", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {["value.key_names"] = "query", name = "keyauth" })
    assert.are.same({
      name = "keyauth",
      value = {
        key_names = { "query" }
      }
    }, result)
  end)

  it("should parse arrays with a correct delimitator", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {["value.key_names"] = "wot,wat", name = "keyauth" })
    assert.are.same({
      name = "keyauth",
      value = {
        key_names = { "wot", "wat" }
      }
    }, result)
  end)

  it("should parse arrays with a incorrect delimitator", function()
    local result = base_controller.parse_params(env.dao_factory.plugins_configurations._schema, {["value.key_names"] = "wot;wat", name = "keyauth" })
    assert.are.same({
      name = "keyauth",
      value = {
        key_names = { "wot;wat" }
      }
    }, result)
  end)

end)
