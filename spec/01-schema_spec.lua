local request_validator_schema = require "kong.plugins.request-validator.schema"
local v = require("spec.helpers").validate_plugin_config_schema


describe("request-validator schema", function()
  it("requires either a body_schema or parameter_schema", function()
    local ok, err = v({}, request_validator_schema)
    assert.is_nil(ok)
    assert.same("at least one of these fields must be non-empty: 'body_schema', " ..
                "'parameter_schema'", err.config["@entity"][1])
  end)

  describe("[Kong-schema]", function()
    it("accepts a valid body_schema", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string"}}]'
      }, request_validator_schema)
      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("errors with an invalid body_schema json", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string}}'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("failed decoding schema: Expected value but found unexpected " ..
                  "end of string at character 29", err["@entity"][1])
    end)

    it("errors with an invalid schema", function()
      local ok, err = v({
        version = "kong",
        body_schema = '[{"name": {"type": "string", "non_existing_field": "bar"}}]'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("schema violation", err["@entity"][1].name)
    end)

    it("errors with an fields specification", function()
      local ok, err = v({
        version = "kong",
        body_schema = '{"name": {"type": "string", "non_existing_field": "bar"}}'
      }, request_validator_schema)
      assert.is_nil(ok)
      assert.same("schema violation", err["@entity"][1].name)
    end)
  end)

  describe("[draft4-schema]", function()
    it("accepts a valid body_schema", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}'
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("errors with an invalid body_schema json", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string}' -- closing bracket missing
      }, request_validator_schema)
      assert.same("failed decoding schema: Expected value but found unexpected " ..
                  "end of string at character 27", err["@entity"][1])
      assert.is_nil(ok)
    end)

    it("errors with an invalid schema", function()
      -- the metaschema references itself, and hence cannot be loaded
      -- to be fixed in ljsonschema lib first
      local ok, err = v({
        version = "draft4",
        body_schema = [[{
            "type": "object",
            "definitions": [ "should have been an object" ]
        }]]
      }, request_validator_schema)
      assert.same("not a valid JSONschema draft 4 schema: property " ..
        "definitions validation failed: wrong type: " ..
        "expected object, got table", err["@entity"][1])
      assert.is_nil(ok)
    end)

    it("accepts allowed_content_type", function()
      local ok, err = v({
        version = "kong",
        allowed_content_types = {
          "application/xml",
          "application/json",
        },
        body_schema = '[{"name": {"type": "string"}}]'
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("does not accepts bad allowed_content_type", function()
      local ok, err = v({
        version = "kong",
        allowed_content_types = {"application/ xml"},
        body_schema = '[{"name": {"type": "string"}}]'
      }, request_validator_schema)
      assert.same("invalid value: application/ xml",
                  err.config.allowed_content_types[1])
      assert.is_nil(ok)
    end)
  end)

  describe("[parameter-schema]", function()
    it("accepts a valid parameter definition ", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "array", "items": {"type": "string"}}',
            style = "simple",
            explode = false,
          }
        }
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("accepts a valid param_schema with type object", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "object", "additionalProperties": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)

    it("errors with invalid param_schema", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "object", "additionalProperties": {"type": "integer"}}',
            style = "simple",
            explode = false,
          },
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            -- wrong type
            schema = '{"type": "objects", "additionalProperties": {"type": "integer"}}',
            style = "simple",
            explode = false,
          }
        }
      }, request_validator_schema)
      assert.same("not a valid JSONschema draft 4 schema: property type validation failed: object matches none of the alternatives", err.config.parameter_schema[2].schema)
      assert.is_nil(ok)
    end)

    it("errors with invalid style", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            schema = '{"type": "object", "additionalProperties": {"type": "integer"}}',
            style = "form",
            explode = false,
          },
        }
      }, request_validator_schema)
      assert.same("style 'form' not supported 'header' parameter", err.config.parameter_schema[1]["@entity"][1])
      assert.is_nil(ok)
    end)

    it("errors with style present but schema missing", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            --schema = '{"type": "object", "additionalProperties": {"type": "integer"}}',
            style = "form",
            explode = false,
          },
        }
      }, request_validator_schema)
      assert.same({
        [1] = "all or none of these fields must be set: 'style', 'explode', 'schema'",
        [2] = "style 'form' not supported 'header' parameter",
      }, err.config.parameter_schema[1]["@entity"])
      assert.is_nil(ok)
    end)

    it("allow without style, schema and explode", function()
      local ok, err = v({
        version = "draft4",
        body_schema = '{"name": {"type": "string"}}',
        parameter_schema = {
          {
            name = "x-kong-name",
            ["in"] = "header",
            required = true,
            --schema = '{"type": "object", "additionalProperties": {"type": "integer"}}',
            --style = "form",
            --explode = false,
          },
        }
      }, request_validator_schema)
      assert.is_nil(err)
      assert.is_truthy(ok)
    end)
  end)

end)
