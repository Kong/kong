-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require("spec.helpers")
local v = helpers.validate_plugin_config_schema
local schema_def

local is_fips = helpers.is_fips_build()

describe("Plugin: ai-proxy-advanced (schema)", function()
  local function setup_global_env()
    _G.kong = _G.kong or {}
    _G.kong.log = _G.kong.log or {
      debug = function(msg)
        ngx.log(ngx.DEBUG, msg)
      end,
      error = function(msg)
        ngx.log(ngx.ERR, msg)
      end,
      warn = function (msg)
        ngx.log(ngx.WARN, msg)
      end
    }
  end

  local previous_kong

  setup(function()
    previous_kong = _G.kong
    setup_global_env()
    local schema_def_path = assert(package.searchpath("kong.plugins.ai-proxy-advanced.schema", package.path))
    schema_def = loadfile(schema_def_path)() -- this way we can avoid conflicts with other tests
  end)

  teardown(function()
    _G.kong = previous_kong
  end)

  it("accepts empty config", function()
    local ok, err = v({ targets = {} }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("accepts targets with same provider", function()

    local ok, err = v({ targets = { {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        provider = "openai",
      },
    }, {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        provider = "openai",
      },
    }} }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("accepts targets with different providers but same format", function()
    local targets = { {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        provider = "openai",
      },
    }, {
      route_type = "llm/v1/chat",
      model = {
        provider = "llama2",
        options = {
          llama2_format = "openai",
          upstream_url = "http://a",
        }
      },
    }, {
      route_type = "llm/v1/chat",
      model = {
        provider = "mistral",
        options = {
          mistral_format = "openai",
          upstream_url = "http://b",
        }
      },
    } }
    local ok, err = v({ targets = targets }, schema_def)
    print(require("inspect")(err))
    assert.is_truthy(ok)
    assert.is_nil(err)

    targets[1], targets[2] = targets[2], targets[1]
    local ok, err = v({ targets = targets }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)

    local ok, err = v({ targets = { {
      route_type = "llm/v1/chat",
      model = {
        provider = "llama2",
        options = {
          llama2_format = "ollama",
          upstream_url = "http://a",
        }
      },
    }, {
      route_type = "llm/v1/chat",
      model = {
        provider = "mistral",
        options = {
          mistral_format = "ollama",
          upstream_url = "http://b",
        }
      },
    } } }, schema_def)
    assert.is_truthy(ok)
    assert.is_nil(err)
  end)

  it("rejects targets with different providers", function()
    local ok, err = v({ targets = { {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        provider = "anthropic",
        options = {
          anthropic_version = "v1",
        }
      },
    }, {
      route_type = "llm/v1/chat",
      auth = {
        header_name = "Authorization",
        header_value = "Bearer token",
      },
      model = {
        provider = "azure",
        options = {
          azure_api_version = "v1",
          azure_instance = "some-instance",
          azure_deployment_id = "some-id",
        }
      },
    } } }, schema_def)
    assert.is_falsy(ok)
    assert.equal("mixing different providers are not supported", err["@entity"][1])
  end)

  it("rejects targets with same providers with different formats", function()
    local ok, err = v({ targets = {{
      route_type = "llm/v1/chat",
      model = {
        provider = "llama2",
        options = {
          llama2_format = "raw",
          upstream_url = "http://a",
        }
      },
    }, {
      route_type = "llm/v1/chat",
      model = {
        provider = "llama2",
        options = {
          llama2_format = "openai",
          upstream_url = "http://a",
        }
      },
    } } }, schema_def)
    assert.is_falsy(ok)
    assert.equal("mixing different providers with different formats are not supported", err["@entity"][1])
  end)
end)
