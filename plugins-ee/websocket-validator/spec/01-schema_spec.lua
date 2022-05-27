-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local schema = require "kong.plugins.websocket-validator.schema"
local v = require("spec.helpers").validate_plugin_config_schema
local cjson = require "cjson"

local fmt = string.format


local function validate(conf)
  return v(conf, schema)
end

local function values(t)
  local i = 0
  return function()
    i = i + 1
    return t[i]
  end
end

local function peers()
  return values({ "client", "upstream" })
end

local function data_types()
  return values({ "text", "binary" })
end

local function non_data_types()
  return values({ "close", "ping", "pong" })
end

local validator = {
  type = "draft4",
  schema = cjson.encode({ type = "string" })
}

describe("plugin(websocket-validator) schema", function()
  it("requires at least one of client/upstream fields", function()
    local ok, err = validate({})
    assert.is_nil(ok)
    assert.same(
      { config = { ["@entity"] = {
          "at least one of these fields must be non-empty: 'client', 'upstream'"
      }}},
      err
    )
  end)

  for peer in peers() do
    it(fmt("requires at least one validator for %s", peer), function()
      local conf = {
        [peer] = {},
      }
      local ok, err = validate(conf)
      assert.is_nil(ok)
      assert.same(
        { [peer] = { ["@entity"] = {
          "at least one of these fields must be non-empty: 'text', 'binary'",
        }}},
        err.config
      )
    end)

    for typ in data_types() do
      it(fmt("accepts %s validators for data frames (%s)", peer, typ), function()
        local conf = {
          [peer] = {
            [typ] = validator,
          },
        }
        local created, err = validate(conf)
        assert.is_nil(err)
        assert.same(validator, created.config[peer][typ])
      end)

      it(fmt("requires `type` for %s %s validation", peer, typ), function()
        local ok, err = validate({
          [peer] = {
            [typ] = {
              schema = cjson.encode({ type = "string" }),
            }
          }
        })
        assert.is_nil(ok)
        assert.same({ type = "required field missing" }, err.config[peer][typ])
      end)

      it(fmt("requires `schema` for %s %s validation", peer, typ), function()
        local ok, err = validate({
          [peer] = {
            [typ] = { type = "draft4" },
          }
        })
        assert.is_nil(ok)
        assert.same({ schema = "required field missing" }, err.config[peer][typ])
      end)
    end

    for typ in non_data_types() do
      it(fmt("does not accept %s validators for non-data frames (%s)", peer, typ), function()
        local conf = {
          [peer] = {
            [typ] = validator,
            text = validator,
            binary = validator,
          },
        }

        local created, err = validate(conf)
        assert.is_nil(created)
        assert.same({ config = {
          [peer] = { [typ] = "unknown field" },
        }}, err)
      end)
    end

  end

  describe("[draft4]", function()
    it("accepts a draft4 JSON schema validator", function()
      local draft4 = {
        type = "draft4",
        schema = cjson.encode({
          type = "object",
          properties = {
            foo = { type = "string" },
            bar = { type = "integer" },
          },
          required = { "foo", "bar" },
        })
      }

      local conf = {
        client = {
          text = draft4,
          binary = draft4,
        },
        upstream = {
          text = draft4,
          binary = draft4,
        },
      }
      local created, err = validate(conf)
      assert.is_nil(err)
      assert.same(conf, created.config)
    end)

    it("rejects invalid JSON", function()
      local conf = {
        client = {
          text = { type = "draft4", schema = "oops" },
          binary = { type = "draft4", schema = "!!!" },
        },
        upstream = {
          text = { type = "draft4", schema = "{" },
          binary= { type = "draft4", schema = "}" },
        },
      }

      local created, err = validate(conf)
      assert.is_nil(created)

      local exp = "^failed decoding schema:"
      assert.matches(exp, err.config.client.text["@entity"][1])
      assert.matches(exp, err.config.client.binary["@entity"][1])
      assert.matches(exp, err.config.upstream.text["@entity"][1])
      assert.matches(exp, err.config.upstream.binary["@entity"][1])
    end)

    it("rejects semantically-invalid JSON schema", function()
      local invalid = {
        type = "draft4",
        schema = cjson.encode({
          type = "object",
          properties = "NOPE",
        })
      }
      local conf = {
        client = {
          text = invalid,
          binary = invalid,
        },
        upstream = {
          text = invalid,
          binary= invalid,
        },
      }

      local created, err = validate(conf)
      assert.is_nil(created)

      local exp = "^not a valid JSONschema draft 4 schema:"
      assert.matches(exp, err.config.client.text["@entity"][1])
      assert.matches(exp, err.config.client.binary["@entity"][1])
      assert.matches(exp, err.config.upstream.text["@entity"][1])
      assert.matches(exp, err.config.upstream.binary["@entity"][1])
    end)
  end)
end)
