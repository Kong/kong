local schema_def = require "kong.plugins.aws-lambda.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("Plugin: AWS Lambda (schema)", function()
  it("accepts nil Unhandled Response Status Code", function()
    local ok, err = v({
      unhandled_status = nil,
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)

  it("accepts correct Unhandled Response Status Code", function()
    local ok, err = v({
      unhandled_status = 412,
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)

  it("errors with Unhandled Response Status Code less than 100", function()
    local ok, err = v({
      unhandled_status = 99,
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.equal("value should be between 100 and 999", err.config.unhandled_status)
    assert.falsy(ok)
  end)

  it("errors with Unhandled Response Status Code greater than 999", function()
    local ok, err = v({
      unhandled_status = 1000,
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.equal("value should be between 100 and 999", err.config.unhandled_status)
    assert.falsy(ok)
  end)

  it("accepts with neither aws_key nor aws_secret", function()
    local ok, err = v({
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)

  it("errors with aws_secret but without aws_key", function()
    local ok, err = v({
      aws_secret = "xx",
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.equal("all or none of these fields must be set: 'config.aws_key', 'config.aws_secret'", err["@entity"][1])
    assert.falsy(ok)
  end)

  it("errors without aws_secret but with aws_key", function()
    local ok, err = v({
      aws_key = "xx",
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.equal("all or none of these fields must be set: 'config.aws_key', 'config.aws_secret'", err["@entity"][1])
    assert.falsy(ok)
  end)

  it("errors with a non-http proxy_url", function()
    for _, scheme in ipairs({"https", "ftp", "wss"}) do
      local ok, err = v({
        proxy_url = scheme .. "://squid:3128",
        aws_region = "us-east-1",
        function_name = "my-function"
      }, schema_def)

      assert.not_nil(err)
      assert.falsy(ok)
      assert.equals("proxy_url scheme must be http", err["@entity"][1])
    end
  end)

  it("accepts a host", function()
    local ok, err = v({
      host = "my.lambda.host",
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)

  it("does not error if none of aws_region and host are passed (tries to autodetect on runtime)", function()
    local ok, err = v({
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)

  it("allow both of aws_region and host to be passed", function()
    local ok, err = v({
      host = "my.lambda.host",
      aws_region = "us-east-1",
      function_name = "my-function"
    }, schema_def)

    assert.is_nil(err)
    assert.truthy(ok)
  end)
end)
