-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jq_schema = require "kong.plugins.jq.schema"
local validate = require("spec.helpers").validate_plugin_config_schema

describe("jq schema", function()
  it("rejects an empty config", function()
    local res, err = validate({}, jq_schema)
    assert.same("at least one of these fields must be non-empty: 'request_jq_program', 'response_jq_program'", err.config["@entity"][1])
    assert.is_falsy(res)
  end)

  it("accepts a minimal config", function()
    local res, err = validate({
      request_jq_program = ".[0]",
    }, jq_schema)
    assert.is_nil(err)
    assert.is_truthy(res)

    assert.same(".[0]", res.config.request_jq_program)
    assert.same({}, res.config.request_jq_program_options)
    assert.same({ "application/json" }, res.config.request_if_media_type)

    assert.same(ngx.null, res.config.response_jq_program)
    assert.same({}, res.config.response_jq_program_options)
    assert.same({ "application/json" }, res.config.response_if_media_type)
    assert.same({ 200 }, res.config.response_if_status_code)
  end)

  it("accepts a complete config", function()
    local res, err = validate({
      request_jq_program = ".[0]",
      request_jq_program_options = {
        compact_output = false,
        raw_output = true,
        join_output = true,
        ascii_output = true,
        sort_keys = true,
      },
      request_if_media_type = { "text/plain" },

      response_jq_program = ".[1]",
      response_jq_program_options = {
        compact_output = false,
        raw_output = true,
        join_output = true,
        ascii_output = false,
        sort_keys = true,
      },
      response_if_media_type = { "text/plain", "application/json" },
      response_if_status_code = { 200, 404 },
    }, jq_schema)

    assert.is_nil(err)
    assert.is_truthy(res)

    assert.same(".[0]", res.config.request_jq_program)
    assert.same({
        compact_output = false,
        raw_output = true,
        join_output = true,
        ascii_output = true,
        sort_keys = true,
    }, res.config.request_jq_program_options)
    assert.same({ "text/plain" }, res.config.request_if_media_type)

    assert.same(".[1]", res.config.response_jq_program)
    assert.same({
      compact_output = false,
      raw_output = true,
      join_output = true,
      ascii_output = false,
      sort_keys = true,
    }, res.config.response_jq_program_options)
    assert.same({ "text/plain", "application/json" }, res.config.response_if_media_type)
    assert.same({ 200, 404 }, res.config.response_if_status_code)
  end)

  it("rejects a config with bad jq_program", function()
    local res, err = validate({
      request_jq_program = "FOO",
    }, jq_schema)
    assert.same("compilation failed: invalid jq program", err.config.request_jq_program)
    assert.is_falsy(res)
  end)

  it("rejects a config with bad jq_options", function()
    local res, err = validate({
      request_jq_program_options = {
        foo = true,
      },
    }, jq_schema)
    assert.same("unknown field", err.config.request_jq_program_options.foo)
    assert.is_falsy(res)
  end)

  it("rejects a config with bad media types", function()
    local res, err = validate({
      request_if_media_type = {
        "application/json",
        "text/json",
        3,
        "foo",
      },
    }, jq_schema)
    assert.same("expected a string", err.config.request_if_media_type[3])
    assert.is_falsy(res)
  end)

  it("rejects a config with bad status codes", function()
    local res, err = validate({
      response_if_status_code = {
        -1,
        25,
        750,
        "foo",
      },
    }, jq_schema)
    assert.same("value should be between 100 and 599",
      err.config.response_if_status_code[3])
    assert.is_falsy(res)
  end)
end)
