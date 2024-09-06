local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"

local strip = require("kong.tools.string").strip

local MOCK_PORT = helpers.get_available_port()
local PLUGIN_NAME = "ai-response-transformer"

local FILE_LOG_PATH_STATS_ONLY = os.tmpname()

local function wait_for_json_log_entry(FILE_LOG_PATH)
  local json

  assert
    .with_timeout(10)
    .ignore_exceptions(true)
    .eventually(function()
      local data = assert(pl_file.read(FILE_LOG_PATH))

      data = strip(data)
      assert(#data > 0, "log file is empty")

      data = data:match("%b{}")
      assert(data, "log file does not contain JSON")

      json = cjson.decode(data)
    end)
    .has_no_error("log file contains a valid JSON entry")

  return json
end

local OPENAI_INSTRUCTIONAL_RESPONSE = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/instructions"
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local OPENAI_FLAT_RESPONSE = {
  route_type = "llm/v1/chat",
  logging = {
    log_payloads = false,
    log_statistics = true,
  },
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/flat",
      input_cost = 10.0,
      output_cost = 10.0,
    },
  },
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
}

local OPENAI_BAD_INSTRUCTIONS = {
  route_type = "llm/v1/chat",
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 512,
      temperature = 0.5,
      upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/badinstructions"
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

local EXPECTED_BAD_INSTRUCTIONS_ERROR = {
  error = {
    message = "failed to parse JSON response instructions from AI backend: Expected value but found invalid token at character 1"
  }
}

local EXPECTED_RESULT = {
  body = [[<persons>
  <person>
    <name>Kong A</name>
    <age>62</age>
  </person>
  <person>
    <name>Kong B</name>
    <age>84</age>
  </person>
</persons>]],
  status = 209,
  headers = {
    ["content-type"] = "application/xml",
  },
}

local _EXPECTED_CHAT_STATS = {
  ["ai-response-transformer"] = {
    meta = {
      plugin_id = 'da587462-a802-4c22-931a-e6a92c5866d1',
      provider_name = 'openai',
      request_model = 'gpt-4',
      response_model = 'gpt-3.5-turbo-0613',
      llm_latency = 1
    },
    usage = {
      prompt_tokens = 25,
      completion_tokens = 12,
      total_tokens = 37,
      time_per_token = 1,
      cost = 0.00037,
    },
    cache = {}
  },
}

local SYSTEM_PROMPT = "You are a mathematician. "
                   .. "Multiply all numbers in my JSON request, by 2. Return me this message: "
                   .. "{\"status\": 400, \"headers: {\"content-type\": \"application/xml\"}, \"body\": \"OUTPUT\"} "
                   .. "where 'OUTPUT' is the result but transformed into XML format."


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

            location ~/instructions {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-with-instructions.json"))
              }
            }

            location ~/flat {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-in-json.json"))
              }
            }

            location ~/badinstructions {
              content_by_lua_block {
                local pl_file = require "pl.file"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/request-transformer/response-with-bad-instructions.json"))
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
      local with_response_instructions = assert(bp.routes:insert {
        paths = { "/echo-parse-instructions" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = with_response_instructions.id },
        config = {
          prompt = SYSTEM_PROMPT,
          parse_llm_response_json_instructions = true,
          llm = OPENAI_INSTRUCTIONAL_RESPONSE,
        },
      }

      local without_response_instructions = assert(bp.routes:insert {
        paths = { "/echo-flat" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        id = "da587462-a802-4c22-931a-e6a92c5866d1",
        route = { id = without_response_instructions.id },
        config = {
          prompt = SYSTEM_PROMPT,
          parse_llm_response_json_instructions = false,
          llm = OPENAI_FLAT_RESPONSE,
        },
      }

      bp.plugins:insert {
        name = "file-log",
        route = { id = without_response_instructions.id },
        config = {
          path = FILE_LOG_PATH_STATS_ONLY,
        },
      }

      local bad_instructions = assert(bp.routes:insert {
        paths = { "/echo-bad-instructions" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = bad_instructions.id },
        config = {
          prompt = SYSTEM_PROMPT,
          parse_llm_response_json_instructions = true,
          llm = OPENAI_BAD_INSTRUCTIONS,
        },
      }

      local bad_instructions_parse_out = assert(bp.routes:insert {
        paths = { "/echo-bad-instructions-parse-out" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = bad_instructions_parse_out.id },
        config = {
          prompt = SYSTEM_PROMPT,
          parse_llm_response_json_instructions = true,
          llm = OPENAI_BAD_INSTRUCTIONS,
          transformation_extract_pattern = "\\{((.|\n)*)\\}",
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
          parse_llm_response_json_instructions = false,
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
          parse_llm_response_json_instructions = false,
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
      helpers.stop_kong()
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("openai response transformer integration", function()
      it("transforms request based on LLM instructions, with response transformation instructions format", function()
        local r = client:get("/echo-parse-instructions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(209 , r)
        assert.same(EXPECTED_RESULT.body, body)
        assert.same(r.headers["content-type"], "application/xml")
      end)

      it("transforms request based on LLM instructions, without response instructions", function()
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
        assert.same(EXPECTED_RESULT_FLAT, body_table)
      end)

      it("logs statistics", function()
        local r = client:get("/echo-flat", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(200 , r)
        local _, err = cjson.decode(body)

        assert.is_nil(err)

        local log_message = wait_for_json_log_entry(FILE_LOG_PATH_STATS_ONLY)
        assert.same("127.0.0.1", log_message.client_ip)
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)

        -- test ai-response-transformer stats
        local actual_chat_stats = log_message.ai
        local actual_llm_latency = actual_chat_stats["ai-response-transformer"].meta.llm_latency
        local actual_time_per_token = actual_chat_stats["ai-response-transformer"].usage.time_per_token
        local time_per_token = math.floor(actual_llm_latency / actual_chat_stats["ai-response-transformer"].usage.completion_tokens)

        log_message.ai["ai-response-transformer"].meta.llm_latency = 1
        log_message.ai["ai-response-transformer"].usage.time_per_token = 1

        assert.same(_EXPECTED_CHAT_STATS, log_message.ai)
        assert.is_true(actual_llm_latency >= 0)
        assert.same(actual_time_per_token, time_per_token)
      end)

      it("fails properly when json instructions are bad", function()
        local r = client:get("/echo-bad-instructions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(500 , r)
        local body_table, err = cjson.decode(body)
        assert.is_nil(err)
        assert.same(EXPECTED_BAD_INSTRUCTIONS_ERROR, body_table)
      end)

      it("succeeds extracting json instructions when bad", function()
        local r = client:get("/echo-bad-instructions-parse-out", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = REQUEST_BODY,
        })

        local body = assert.res_status(209 , r)
        assert.same(EXPECTED_RESULT.body, body)
        assert.same(r.headers["content-type"], "application/xml")
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
