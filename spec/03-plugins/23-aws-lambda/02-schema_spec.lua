local schema_def = require "kong.plugins.aws-lambda.schema"
local utils = require "kong.tools.utils"
local validate_plugin_config_schema = require("spec.helpers").validate_plugin_config_schema


local DEFAULTS = {
  timeout          = 60000,
  keepalive        = 60000,
  aws_key          = "my-key",
  aws_secret       = "my-secret",
  aws_region       = "us-east-1",
  function_name    = "my-function",
  invocation_type  = "RequestResponse",
  log_type         = "Tail",
  port             = 443,
}


local function v(config)
  return validate_plugin_config_schema(
    utils.table_merge(DEFAULTS, config),
    schema_def
  )
end


describe("Plugin: AWS Lambda (schema)", function()
  it("accepts nil Unhandled Response Status Code", function()
    local ok, err = v({ unhandled_status = nil })
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  it("accepts correct Unhandled Response Status Code", function()
    local ok, err = v({ unhandled_status = 412 })
    assert.truthy(ok)
    assert.is_nil(err)
  end)

  it("errors with Unhandled Response Status Code less than 100", function()
    local ok, err = v({ unhandled_status = 99 })
    assert.falsy(ok)
    assert.equal("value should be between 100 and 999", err.config.unhandled_status)
  end)

  it("errors with Unhandled Response Status Code greater than 999", function()
    local ok, err = v({ unhandled_status = 1000 })
    assert.falsy(ok)
    assert.equal("value should be between 100 and 999", err.config.unhandled_status)
  end)
end)
