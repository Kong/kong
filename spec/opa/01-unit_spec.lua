local PLUGIN_NAME = "opa"
local decision = require "kong.plugins.opa.decision"


local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()


  it("errors without any configuration options", function()
    local _, err = validate({})
    assert.is_not_nil(err)
  end)


  it("works when opa_path is provided", function()
    local ok, err = validate({ opa_path = "/foo" })
    assert.is_nil(err)
    assert.same(ok.config, {
      opa_protocol = "http",
      opa_host = "localhost",
      opa_port = 80,
      opa_path = "/foo",
      include_service_in_opa_input = false,
      include_route_in_opa_input = false,
      include_consumer_in_opa_input = false,
    })
  end)


end)


describe(PLUGIN_NAME .. ": (process_decision)", function()


  it("errors without decision", function()
    local allow, response, err = decision.process_decision()
    assert.is_not_nil(err)
    assert.is_nil(allow)
    assert.is_nil(response)
  end)


  it("allows request when decision is positive", function()
    local allow, response, err = decision.process_decision({
      result = true,
    })
    assert.is_nil(err)
    assert.same(allow, true)
    assert.is_nil(response)
  end)


  it("denys request when decision is positive", function()
    local allow, response, err = decision.process_decision({
      result = false,
    })
    assert.is_nil(err)
    assert.same(allow, false)
    assert.is_nil(response)
  end)


  it("errors when result is not a table or boolean", function()
    local allow, response, err = decision.process_decision({
      result = "42",
    })
    assert.is_not_nil(err)
    assert.is_nil(allow)
    assert.is_nil(response)
  end)


  it("errors when result is nil", function()
    local allow, response, err = decision.process_decision({
      result = nil,
    })
    assert.is_not_nil(err)
    assert.is_nil(allow)
    assert.is_nil(response)
  end)


  it("errors when result.allow is not a boolean", function()
    local allow, response, err = decision.process_decision({
      result = {
        allow = "true",
      },
    })
    assert.is_not_nil(err)
    assert.is_nil(allow)
    assert.is_nil(response)
  end)


  it("allows when result.allow is true", function()
    local allow, response, err = decision.process_decision({
      result = {
        allow = true,
      },
    })
    assert.is_nil(err)
    assert.same(allow, true)
    assert.same(response, {})
  end)


  it("denys when result.allow is false", function()
    local allow, response, err = decision.process_decision({
      result = {
        allow = false,
      },
    })
    assert.is_nil(err)
    assert.same(allow, false)
    assert.same(response, {})
  end)


  it("sets header and status", function()
    local allow, response, err = decision.process_decision({
      result = {
        allow = false,
        headers = {
          bob = "dylan",
        },
        status = 418,
      },
    })
    assert.is_nil(err)
    assert.same(allow, false)
    assert.same(response, { headers = { bob = "dylan" }, status = 418 })
  end)


end)

