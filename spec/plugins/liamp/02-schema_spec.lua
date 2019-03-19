local aws_lambda_schema = require "kong.plugins.liamp.schema"
local schemas           = require "kong.dao.schemas_validation"
local utils             = require "kong.tools.utils"


local validate_entity   = schemas.validate_entity


describe("Plugin: AWS Lambda (schema)", function()
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

  it("accepts nil Unhandled Response Status Code", function()
    local entity = utils.table_merge(DEFAULTS, { unhandled_status = nil })
    local ok, err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.True(ok)
  end)

  it("accepts correct Unhandled Response Status Code", function()
    local entity = utils.table_merge(DEFAULTS, { unhandled_status = 412 })
    local ok, err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.True(ok)
  end)

  it("errors with Unhandled Response Status Code less than 100", function()
    local entity = utils.table_merge(DEFAULTS, { unhandled_status = 99 })
    local ok, err = validate_entity(entity, aws_lambda_schema)
    assert.equal("unhandled_status must be within 100 - 999.", err.unhandled_status)
    assert.False(ok)
  end)

  it("errors with Unhandled Response Status Code greater than 999", function()
    local entity = utils.table_merge(DEFAULTS, { unhandled_status = 1000 })
    local ok, err = validate_entity(entity, aws_lambda_schema)
    assert.equal("unhandled_status must be within 100 - 999.", err.unhandled_status)
    assert.False(ok)
  end)

  it("accepts with neither aws_key nor aws_secret", function()
    local entity = utils.table_merge(DEFAULTS, { aws_key = "", aws_secret = "" })
    local ok, err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.True(ok)
  end)

  it("errors with aws_secret but without aws_key", function()
    local entity = utils.table_merge(DEFAULTS, { aws_secret = "xx", aws_key = "" })
    local ok, err, self_err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.equal("You need to set both or neither of aws_key and aws_secret", self_err.message)
    assert.False(ok)
  end)

  it("errors without aws_secret but with aws_key", function()
    local entity = utils.table_merge(DEFAULTS, { aws_secret = "", aws_key = "xx" })
    local ok, err, self_err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.equal("You need to set both or neither of aws_key and aws_secret", self_err.message)
    assert.False(ok)
  end)

  it("errors if proxy_scheme is missing while proxy_url is provided", function()
    local entity = utils.table_merge(DEFAULTS, { proxy_url = "http://hello.com/proxy" })
    local ok, err, self_err = validate_entity(entity, aws_lambda_schema)
    assert.is_nil(err)
    assert.equal("You need to set proxy_scheme when proxy_url is set", self_err.message)
    assert.False(ok)
  end)

end)
