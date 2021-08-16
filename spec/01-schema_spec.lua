-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jq_filter_schema = require "kong.plugins.jq.schema"
local validate = require("spec.helpers").validate_plugin_config_schema

describe("jq schema", function()
  it("rejects empty config", function()
    local ok, err = validate({}, jq_filter_schema)
    assert.is_falsy(ok)
    assert.same("required field missing", err.config.filters)
  end)

  it("accepts a minimal config", function()
    local res, err = validate({
      filters = {
        { program = "." }
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)

    assert.same("body", res.config.filters[1].target)
    assert.same({}, res.config.filters[1].jq_options)
    assert.same({ "application/json" }, res.config.filters[1].if_media_type)
  end)

  it("rejects a config with bad context", function()
    local res, err = validate({
      filters = {
        {
          context = "foo",
          program = ".",
        },
      }
    }, jq_filter_schema)
    assert.same("expected one of: request, response", err.config.filters[1].context)
    assert.is_falsy(res)
  end)

  it("accepts a config with request context", function()
    local res, err = validate({
      filters = {
        {
          context = "request",
          program = ".",
        },
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)

    assert.same("request", res.config.filters[1].context)
  end)

  it("rejects a config with bad target", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          target = "foo",
        },
      }
    }, jq_filter_schema)
    assert.same("expected one of: body, headers", err.config.filters[1].target)
    assert.is_falsy(res)
  end)

  it("accepts a config with target headers", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          target = "headers",
        },
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)

    assert.same("headers", res.config.filters[1].target)
  end)

  it("rejects a config with bad jq_options", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          jq_options = {
            foo = true,
          },
        },
      }
    }, jq_filter_schema)
    assert.same("unknown field", err.config.filters[1].jq_options.foo)
    assert.is_falsy(res)
  end)

  it("accepts a config with full jq_options", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          jq_options = {
            compact_output = false,
            raw_output = true,
            join_output = true,
            ascii_output = true,
            sort_keys = true,
          },
        },
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)

    assert.is_falsy(res.config.filters[1].jq_options.compact_output)
    assert.is_truthy(res.config.filters[1].jq_options.raw_output)
    assert.is_truthy(res.config.filters[1].jq_options.join_output)
    assert.is_truthy(res.config.filters[1].jq_options.ascii_output)
    assert.is_truthy(res.config.filters[1].jq_options.sort_keys)
  end)

  it("rejects a config with bad media types", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          if_media_type = {
            "application/json",
            "text/json",
            3,
            "foo",
          },
        },
      }
    }, jq_filter_schema)
    assert.same("expected a string", err.config.filters[1].if_media_type[3])
    assert.is_falsy(res)
  end)

  it("accepts a config with explicit media types", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          if_media_type = {
            "application/json",
            "text/json",
          },
        },
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)
  end)

  it("rejects a config with bad status codes", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          if_status_code = {
            -1,
            25,
            750,
            "foo",
          },
        },
      }
    }, jq_filter_schema)
    assert.same("value should be between 100 and 599",
      err.config.filters[1].if_status_code[3])
    assert.is_falsy(res)
  end)

  it("accepts a config with valid status codes", function()
    local res, err = validate({
      filters = {
        {
          program = ".",
          if_status_code = {
            200,
            201,
            404,
          },
        },
      }
    }, jq_filter_schema)
    assert.is_nil(err)
    assert.is_truthy(res)
  end)
end)
