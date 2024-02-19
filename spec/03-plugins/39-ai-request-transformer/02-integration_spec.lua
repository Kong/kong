local helpers = require "spec.helpers"
local cjson = require "cjson"

local MOCK_PORT = helpers.get_available_port()
local PLUGIN_NAME = "ai-request-transformer"

local OPENAI_FLAT_RESPONSE = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/flat"
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local OPENAI_BAD_REQUEST = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/badrequest"
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local OPENAI_INTERNAL_SERVER_ERROR = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/internalservererror"
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

local EXPECTED_RESULT_FLAT = {
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
                   .. "Multiply all numbers in my JSON request, by 2."


local client

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up provider fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.openai = [[
        server {
            server_name llm;
            listen ]]..MOCK_PORT..[[;
            
            default_type 'application/json';

            location ~/flat {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-in-json.json"))
              }
            }

            location = "/badrequest" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                
                ngx.status = 400
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
              }
            }

            location = "/internalservererror" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                
                ngx.status = 500
                ngx.header["content-type"] = "text/html"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/internal_server_error.html"))
              }
            }
        }
      ]]

      -- echo server via 'openai' LLM
      local without_response_instructions = assert(bp.routes:insert {
        paths = { "/echo-flat" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = without_response_instructions.id },
        config = {
          prompt = SYSTEM_PROMPT,
          llm = OPENAI_FLAT_RESPONSE,
        },
      }

      local bad_request = assert(bp.routes:insert {
        paths = { "/echo-bad-request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = bad_request.id },
        config = {
          prompt = SYSTEM_PROMPT,
          llm = OPENAI_BAD_REQUEST,
        },
      }

      local internal_server_error = assert(bp.routes:insert {
        paths = { "/echo-internal-server-error" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = internal_server_error.id },
        config = {
          prompt = SYSTEM_PROMPT,
          llm = OPENAI_INTERNAL_SERVER_ERROR,
        },
      }
      --

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

    describe("openai response transformer integration", function()
      it("transforms properly from LLM", function()
        local r = client:get("/echo-flat", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })
        
        local body = assert.res_status(200 , r)
        local body_table, err = cjson.decode(body)

        assert.is_nil(err)
        assert.same(EXPECTED_RESULT_FLAT, body_table.post_data.params)
      end)

      it("bad request from LLM", function()
        local r = client:get("/echo-bad-request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(400 , r)
        local body_table, err = cjson.decode(body)

        assert.is_nil(err)
        assert.same({ error = { message = "failed to introspect request with AI service: status code 400" }}, body_table)
      end)

      it("internal server error from LLM", function()
        local r = client:get("/echo-internal-server-error", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(400 , r)
        local body_table, err = cjson.decode(body)

        assert.is_nil(err)
        assert.same({ error = { message = "failed to introspect request with AI service: status code 500" }}, body_table)
      end)
    end)
  end)
end
end
