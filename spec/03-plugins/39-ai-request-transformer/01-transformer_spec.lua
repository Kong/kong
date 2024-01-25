local llm_class = require("kong.llm")
local helpers = require "spec.helpers"
local cjson = require "cjson"

local MOCK_PORT = 62349
local PLUGIN_NAME = "ai-request-transformer"

local FORMATS = {
  openai = {
    route_type = "llm/v1/chat",
    model = {
      name = "gpt-4",
      provider = "openai",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/openai"
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer openai-key",
    },
  },
  cohere = {
    route_type = "llm/v1/chat",
    model = {
      name = "command",
      provider = "cohere",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/cohere"
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer cohere-key",
    },
  },
  authropic = {
    route_type = "llm/v1/chat",
    model = {
      name = "claude-2",
      provider = "anthropic",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/anthropic"
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer anthropic-key",
    },
  },
  azure = {
    route_type = "llm/v1/chat",
    model = {
      name = "gpt-4",
      provider = "azure",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/azure"
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer azure-key",
    },
  },
  llama2 = {
    route_type = "llm/v1/chat",
    model = {
      name = "llama2",
      provider = "llama2",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/llama2",
        llama2_format = "raw",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer llama2-key",
    },
  },
  mistral = {
    route_type = "llm/v1/chat",
    model = {
      name = "mistral",
      provider = "mistral",
      options = {
        max_tokens = 512,
        temperature = 0.5,
        upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/chat/mistral",
        mistral_format = "ollama",
      },
    },
    auth = {
      header_name = "Authorization",
      header_value = "Bearer mistral-key",
    },
  },
}

local OPENAI_NOT_JSON = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/not-json"
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local REQUEST_BODY = [[
  {
    "persons": [
      {
        "name": "Kong A",
        "age": 31
      },
      {
        "name": "Kong B",
        "age": 42
      }
    ]
  }
]]

local EXPECTED_RESULT = {
  persons = {
    [1] = {
      age = 62,
      name = "Kong A"
    },
    [2] = {
      age = 84,
      name = "Kong B"
    },
  }
}

local SYSTEM_PROMPT = "You are a mathematician. "
                   .. "Multiply all numbers in my JSON request, by 2. Return me the JSON output only"


local client


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then

  describe(PLUGIN_NAME .. ": (unit)", function()

    lazy_setup(function()
      -- set up provider fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.openai = [[
        server {
            server_name llm;
            listen ]]..MOCK_PORT..[[;
            
            default_type 'application/json';

            location ~/chat/(?<provider>[a-z0-9]+) {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                local token = ngx.req.get_headers()["authorization"]
                local token_query = ngx.req.get_uri_args()["apikey"]

                if token == "Bearer " .. ngx.var.provider .. "-key" or token_query == "$1-key" or body.apikey == "$1-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)
                  
                  if err or (body.messages == ngx.null) then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/" .. ngx.var.provider .. "/llm-v1-chat/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/" .. ngx.var.provider .. "/request-transformer/response-in-json.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/" .. ngx.var.provider .. "/llm-v1-chat/responses/unauthorized.json"))
                end
              }
            }

            location ~/not-json {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-not-json.json"))
              }
            }
        }
      ]]

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }, nil, nil, fixtures))
    end)
    
    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    for name, format_options in pairs(FORMATS) do

      describe(name .. " transformer tests, exact json response", function()

        it("transforms request based on LLM instructions", function()
          local llm = llm_class:new(format_options, {})
          assert.truthy(llm)

          local result, err = llm:ai_introspect_body(
            REQUEST_BODY,  -- request body
            SYSTEM_PROMPT, -- conf.prompt
            {},            -- http opts
            nil            -- transformation extraction pattern
          )

          assert.is_nil(err)

          result, err = cjson.decode(result)
          assert.is_nil(err)

          assert.same(EXPECTED_RESULT, result)
        end)
      end)

      
    end

    describe("openai transformer tests, pattern matchers", function()
      it("transforms request based on LLM instructions, with json extraction pattern", function()
        local llm = llm_class:new(OPENAI_NOT_JSON, {})
        assert.truthy(llm)

        local result, err = llm:ai_introspect_body(
          REQUEST_BODY,  -- request body
          SYSTEM_PROMPT, -- conf.prompt
          {},            -- http opts
          "\\{((.|\n)*)\\}" -- transformation extraction pattern (loose json)
        )

        assert.is_nil(err)

        result, err = cjson.decode(result)
        assert.is_nil(err)

        assert.same(EXPECTED_RESULT, result)
      end)

      it("transforms request based on LLM instructions, but fails to match pattern", function()
        local llm = llm_class:new(OPENAI_NOT_JSON, {})
        assert.truthy(llm)

        local result, err = llm:ai_introspect_body(
          REQUEST_BODY,  -- request body
          SYSTEM_PROMPT, -- conf.prompt
          {},            -- http opts
          "\\#*\\=" -- transformation extraction pattern (loose json)
        )

        assert.is_nil(result)
        assert.is_not_nil(err)
        assert.same("AI response did not match specified regular expression", err)
      end)
    end)
  end)
end end
