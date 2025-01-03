local helpers = require "spec.helpers"
local cjson = require "cjson.safe"
local pl_file = require "pl.file"
local strip = require("kong.tools.string").strip

local http = require("resty.http")

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

local FILE_LOG_PATH_WITH_PAYLOADS = os.tmpname()

local _EXPECTED_CHAT_STATS = {
  meta = {
    plugin_id = '6e7c40f6-ce96-48e4-a366-d109c169e444',
    provider_name = 'openai',
    request_model = 'gpt-3.5-turbo',
    response_model = 'gpt-3.5-turbo',
    llm_latency = 1
  },
  usage = {
    prompt_tokens = 18,
    completion_tokens = 13, -- this was from estimation
    total_tokens = 31,
    time_per_token = 1,
    cost = 0.00031,
  },
}

local truncate_file = function(path)
  local file = io.open(path, "w")
  file:close()
end

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

for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy  .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up openai mock fixtures
      local fixtures = {
        http_mock = {},
        dns_mock = helpers.dns_mock.new({
          mocks_only = true,      -- don't fallback to "real" DNS
        }),
      }

      fixtures.dns_mock:A {
        name = "api.openai.com",
        address = "127.0.0.1",
      }

      fixtures.dns_mock:A {
        name = "api.cohere.com",
        address = "127.0.0.1",
      }

      fixtures.http_mock.streams = [[
        server {
          server_name openai;
          listen ]]..MOCK_PORT..[[;

          default_type 'application/json';
          chunked_transfer_encoding on;
          proxy_buffering on;
          proxy_buffer_size 600;
          proxy_buffers 10 600;

          location = "/openai/llm/v1/chat/good" {
            content_by_lua_block {
              local _EVENT_CHUNKS = {
                [1] = 'data: {    "choices": [        {            "delta": {                "content": "",                "role": "assistant"            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [2] = 'data: {    "choices": [        {            "delta": {                "content": "The "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}\n\ndata: {    "choices": [        {            "delta": {                "content": "answer "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [3] = 'data: {    "choices": [        {            "delta": {                "content": "to 1 + "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [4] = 'data: {    "choices": [        {            "delta": {                "content": "1 is "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}\n\ndata: {    "choices": [        {            "delta": {                "content": "2."            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [5] = 'data: {    "choices": [        {            "delta": {},            "finish_reason": "stop",            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [6] = 'data: [DONE]',
              }

              local fmt = string.format
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  -- GOOD RESPONSE

                  ngx.status = 200
                  ngx.header["Content-Type"] = "text/event-stream"

                  for i, EVENT in ipairs(_EVENT_CHUNKS) do
                    ngx.print(fmt("%s\n\n", EVENT))
                  end
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          location = "/openai/llm/v1/chat/partial" {
            content_by_lua_block {
              local _EVENT_CHUNKS = {
                [1] = 'data: {    "choices": [        {            "delta": {                "content": "",                "role": "assistant"            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [2] = 'data: {    "choices": [        {            "delta": {                "content": "The "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}\n\ndata: {    "choices": [        {            "delta": {                "content": "answer "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [3] = 'data: {    "choices": [        {            "delta": {                "content": "to 1 + "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Ts',
                [4] = 'w1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [5] = 'data: {    "choices": [        {            "delta": {                "content": "1 is "            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}\n\ndata: {    "choices": [        {            "delta": {                "content": "2."            },            "finish_reason": null,            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [6] = 'data: {    "choices": [        {            "delta": {},            "finish_reason": "stop",            "index": 0,            "logprobs": null        }    ],    "created": 1712538905,    "id": "chatcmpl-9BXtBvU8Tsw1U7CarzV71vQEjvYwq",    "model": "gpt-4-0613",    "object": "chat.completion.chunk",    "system_fingerprint": null}',
                [7] = 'data: [DONE]',
              }

              local fmt = string.format
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  -- GOOD RESPONSE

                  ngx.status = 200
                  ngx.header["Content-Type"] = "text/event-stream"

                  for i, EVENT in ipairs(_EVENT_CHUNKS) do
                    -- pretend to truncate chunks
                    if _EVENT_CHUNKS[i+1] and _EVENT_CHUNKS[i+1]:sub(1, 5) ~= "data:" then
                      ngx.print(EVENT)
                    else  
                      ngx.print(fmt("%s\n\n", EVENT))
                    end
                  end
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          location = "/cohere/llm/v1/chat/good" {
            content_by_lua_block {
              local _EVENT_CHUNKS = {
                [1] = '{"is_finished":false,"event_type":"stream-start","generation_id":"3f41d0ea-0d9c-4ecd-990a-88ba46ede663"}',
                [2] = '{"is_finished":false,"event_type":"text-generation","text":"1"}',
                [3] = '{"is_finished":false,"event_type":"text-generation","text":" +"}',
                [4] = '{"is_finished":false,"event_type":"text-generation","text":" 1"}',
                [5] = '{"is_finished":false,"event_type":"text-generation","text":" ="}',
                [6] = '{"is_finished":false,"event_type":"text-generation","text":" 2"}',
                [7] = '{"is_finished":false,"event_type":"text-generation","text":"."}\n\n{"is_finished":false,"event_type":"text-generation","text":" This"}',
                [8] = '{"is_finished":false,"event_type":"text-generation","text":" is"}',
                [9] = '{"is_finished":false,"event_type":"text-generation","text":" the"}',
                [10] = '{"is_finished":false,"event_type":"text-generation","text":" most"}\n\n{"is_finished":false,"event_type":"text-generation","text":" basic"}',
                [11] = '{"is_finished":false,"event_type":"text-generation","text":" example"}\n\n{"is_finished":false,"event_type":"text-generation","text":" of"}\n\n{"is_finished":false,"event_type":"text-generation","text":" addition"}',
                [12] = '{"is_finished":false,"event_type":"text-generation","text":"."}',
                [13] = '{"is_finished":true,"event_type":"stream-end","response":{"response_id":"4658c450-4755-4454-8f9e-a98dd376b9ad","text":"1 + 1 = 2. This is the most basic example of addition.","generation_id":"3f41d0ea-0d9c-4ecd-990a-88ba46ede663","chat_history":[{"role":"USER","message":"What is 1 + 1?"},{"role":"CHATBOT","message":"1 + 1 = 2. This is the most basic example of addition, an arithmetic operation that involves combining two or more numbers together to find their sum. In this case, the numbers being added are both 1, and the answer is 2, meaning 1 + 1 = 2 is an algebraic equation that shows the relationship between these two numbers when added together. This equation is often used as an example of the importance of paying close attention to details when doing math problems, because it is surprising to some people that something so trivial as adding 1 + 1 could ever equal anything other than 2."}],"meta":{"api_version":{"version":"1"},"billed_units":{"input_tokens":57,"output_tokens":123},"tokens":{"input_tokens":68,"output_tokens":123}}},"finish_reason":"COMPLETE"}',
              }

              local fmt = string.format
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "Bearer cohere-key" or token_query == "cohere-key" or body.apikey == "cohere-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  -- GOOD RESPONSE

                  ngx.status = 200
                  ngx.header["Content-Type"] = "text/event-stream"

                  for i, EVENT in ipairs(_EVENT_CHUNKS) do
                    ngx.print(fmt("%s\n\n", EVENT))
                  end
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          location = "/anthropic/llm/v1/chat/good" {
            content_by_lua_block {
              local _EVENT_CHUNKS = {
                [1] = 'event: message_start',
                [2] = 'event: content_block_start',
                [3] = 'event: ping',
                [4] = 'event: content_block_delta',
                [5] = 'event: content_block_delta',
                [6] = 'event: content_block_delta',
                [7] = 'event: content_block_delta',
                [8] = 'event: content_block_delta',
                [9] = 'event: content_block_stop',
                [10] = 'event: message_delta',
                [11] = 'event: message_stop',
              }

              local _DATA_CHUNKS = {
                [1] = 'data: {"type":"message_start","message":{"id":"msg_013NVLwA2ypoPDJAxqC3G7wg","type":"message","role":"assistant","model":"claude-2.1","stop_sequence":null,"usage":{"input_tokens":15,"output_tokens":1},"content":[],"stop_reason":null}          }',
                [2] = 'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}    }',
                [3] = 'data: {"type": "ping"}',
                [4] = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"1"}       }',
                [5] = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" +"}               }',
                [6] = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" 1"}               }',
                [7] = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" ="}               }',
                [8] = 'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" 2"}               }',
                [9] = 'data: {"type":"content_block_stop","index":0           }',
                [10] = 'data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":9}}',
                [11] = 'data: {"type":"message_stop"}',
              }

              local fmt = string.format
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["api-key"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "anthropic-key" or token_query == "anthropic-key" or body.apikey == "anthropic-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  -- GOOD RESPONSE

                  ngx.status = 200
                  ngx.header["Content-Type"] = "text/event-stream"

                  for i, EVENT in ipairs(_EVENT_CHUNKS) do
                    ngx.print(fmt("%s\n", EVENT))
                    ngx.print(fmt("%s\n\n", _DATA_CHUNKS[i]))
                  end
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          location = "/openai/llm/v1/chat/bad" {
            content_by_lua_block {
              local fmt = string.format
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              ngx.req.read_body()
              local body, err = ngx.req.get_body_data()
              body, err = json.decode(body)

              local token = ngx.req.get_headers()["authorization"]
              local token_query = ngx.req.get_uri_args()["apikey"]

              if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  -- BAD RESPONSE

                  ngx.status = 400

                  ngx.say('{"error": { "message": "failure of some kind" }}')
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }
        }
      ]]

      local empty_service = assert(bp.services:insert {
        name = "empty_service",
        host = "localhost",
        port = 8080,
        path = "/",
      })

      -- 200 chat openai
      local openai_chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = openai_chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/openai/llm/v1/chat/good",
              input_cost = 10.0,
              output_cost = 10.0,
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = openai_chat_good.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 200 chat openai - PARTIAL SPLIT CHUNKS
      local openai_chat_partial = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/partial" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        id = "6e7c40f6-ce96-48e4-a366-d109c169e444",
        route = { id = openai_chat_partial.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          logging = {
            log_payloads = true,
            log_statistics = true,
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/openai/llm/v1/chat/partial",
              input_cost = 10.0,
              output_cost = 10.0,
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = openai_chat_partial.id },
        config = {
          path = FILE_LOG_PATH_WITH_PAYLOADS,
        },
      }
      --

      -- 200 chat cohere
      local cohere_chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/cohere/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = cohere_chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer cohere-key",
          },
          model = {
            name = "command",
            provider = "cohere",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/cohere/llm/v1/chat/good",
              input_cost = 10.0,
              output_cost = 10.0,
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = cohere_chat_good.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 200 chat anthropic
      local anthropic_chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = anthropic_chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/anthropic/llm/v1/chat/good",
              anthropic_version = "2023-06-01",
              input_cost = 10.0,
              output_cost = 10.0,
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = anthropic_chat_good.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 400 chat openai
      local openai_chat_bad = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/bad" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = openai_chat_bad.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/openai/llm/v1/chat/bad",
              input_cost = 10.0,
              output_cost = 10.0,
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = openai_chat_bad.id },
        config = {
          path = "/dev/stdout",
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
      os.remove(FILE_LOG_PATH_WITH_PAYLOADS)
    end)

    before_each(function()
      client = helpers.proxy_client()
      truncate_file(FILE_LOG_PATH_WITH_PAYLOADS)
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("stream llm/v1/chat", function()
      it("good stream request openai", function()
        local httpc = http.new()

        local ok, err, _ = httpc:connect({
          scheme = "http",
          host = helpers.mock_upstream_host,
          port = helpers.get_proxy_port(),
        })
        if not ok then
          assert.is_nil(err)
        end

        -- Then send using `request`, supplying a path and `Host` header instead of a
        -- full URI.
        local res, err = httpc:request({
            path = "/openai/llm/v1/chat/good",
            body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good-stream.json"),
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
        })
        if not res then
          assert.is_nil(err)
        end

        local reader = res.body_reader
        local buffer_size = 35536
        local events = {}
        local buf = require("string.buffer").new()

        -- extract event
        repeat
          -- receive next chunk
          local buffer, err = reader(buffer_size)
          if err then
            assert.is_falsy(err and err ~= "closed")
          end

          if buffer then
            -- we need to rip each message from this chunk
            for s in buffer:gmatch("[^\r\n]+") do
              local s_copy = s
              s_copy = string.sub(s_copy,7)
              s_copy = cjson.decode(s_copy)

              buf:put(s_copy
                    and s_copy.choices
                    and s_copy.choices
                    and s_copy.choices[1]
                    and s_copy.choices[1].delta
                    and s_copy.choices[1].delta.content
                    or "")

              table.insert(events, s)
            end
          end
        until not buffer

        assert.equal(#events, 8)
        assert.equal(buf:tostring(), "The answer to 1 + 1 is 2.")
        -- to verifiy not enable `kong.service.request.enable_buffering()`
        assert.logfile().has.no.line("/kong_buffered_http", true, 10)
      end)

      it("good stream request openai with partial split chunks", function()
        local httpc = http.new()

        local ok, err, _ = httpc:connect({
          scheme = "http",
          host = helpers.mock_upstream_host,
          port = helpers.get_proxy_port(),
        })
        if not ok then
          assert.is_nil(err)
        end

        -- Then send using `request`, supplying a path and `Host` header instead of a
        -- full URI.
        local res, err = httpc:request({
            path = "/openai/llm/v1/chat/partial",
            body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good-stream.json"),
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
        })
        if not res then
          assert.is_nil(err)
        end

        local reader = res.body_reader
        local buffer_size = 35536
        local events = {}
        local buf = require("string.buffer").new()

        -- extract event
        repeat
          -- receive next chunk
          local buffer, err = reader(buffer_size)
          if err then
            assert.is_falsy(err and err ~= "closed")
          end

          if buffer then
            -- we need to rip each message from this chunk
            for s in buffer:gmatch("[^\r\n]+") do
              local s_copy = s
              s_copy = string.sub(s_copy,7)
              s_copy = cjson.decode(s_copy)

              buf:put(s_copy
                    and s_copy.choices
                    and s_copy.choices
                    and s_copy.choices[1]
                    and s_copy.choices[1].delta
                    and s_copy.choices[1].delta.content
                    or "")

              table.insert(events, s)
            end
          end
        until not buffer

        assert.equal(#events, 8)
        assert.equal(buf:tostring(), "The answer to 1 + 1 is 2.")

        -- test analytics on this item
        local log_message = wait_for_json_log_entry(FILE_LOG_PATH_WITH_PAYLOADS)
        assert.same("127.0.0.1", log_message.client_ip)
        assert.is_number(log_message.request.size)
        assert.is_number(log_message.response.size)

        local actual_stats = log_message.ai.proxy

        local actual_llm_latency = actual_stats.meta.llm_latency
        local actual_time_per_token = actual_stats.usage.time_per_token
        local time_per_token = actual_llm_latency / actual_stats.usage.completion_tokens

        local actual_request_log = actual_stats.payload.request or "ERROR: NONE_RETURNED"
        local actual_response_log = actual_stats.payload.response or "ERROR: NONE_RETURNED"
        actual_stats.payload = nil

        actual_stats.meta.llm_latency = 1
        actual_stats.usage.time_per_token = 1

        assert.same(_EXPECTED_CHAT_STATS, actual_stats)
        assert.is_true(actual_llm_latency >= 0)
        assert.same(tonumber(string.format("%.3f", actual_time_per_token)), tonumber(string.format("%.3f", time_per_token)))
        assert.match_re(actual_request_log, [[.*content.*What is 1 \+ 1.*]])
        assert.match_re(actual_response_log, [[.*content.*The answer.*]])
        -- to verifiy not enable `kong.service.request.enable_buffering()`
        assert.logfile().has.no.line("/kong_buffered_http", true, 10)
      end)

      it("good stream request cohere", function()
        local httpc = http.new()

        local ok, err, _ = httpc:connect({
          scheme = "http",
          host = helpers.mock_upstream_host,
          port = helpers.get_proxy_port(),
        })
        if not ok then
          assert.is_nil(err)
        end

        -- Then send using `request`, supplying a path and `Host` header instead of a
        -- full URI.
        local res, err = httpc:request({
            path = "/cohere/llm/v1/chat/good",
            body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good-stream.json"),
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
        })
        if not res then
          assert.is_nil(err)
        end

        local reader = res.body_reader
        local buffer_size = 35536
        local events = {}
        local buf = require("string.buffer").new()

        -- extract event
        repeat
          -- receive next chunk
          local buffer, err = reader(buffer_size)
          if err then
            assert.is_falsy(err and err ~= "closed")
          end

          if buffer then
            -- we need to rip each message from this chunk
            for s in buffer:gmatch("[^\r\n]+") do
              local s_copy = s
              s_copy = string.sub(s_copy,7)
              s_copy = cjson.decode(s_copy)

              buf:put(s_copy
                    and s_copy.choices
                    and s_copy.choices
                    and s_copy.choices[1]
                    and s_copy.choices[1].delta
                    and s_copy.choices[1].delta.content
                    or "")
              table.insert(events, s)
            end
          end
        until not buffer

        assert.equal(#events, 17)
        assert.equal(buf:tostring(), "1 + 1 = 2. This is the most basic example of addition.")
        -- to verifiy not enable `kong.service.request.enable_buffering()`
        assert.logfile().has.no.line("/kong_buffered_http", true, 10)
      end)

      it("good stream request anthropic", function()
        local httpc = http.new()

        local ok, err, _ = httpc:connect({
          scheme = "http",
          host = helpers.mock_upstream_host,
          port = helpers.get_proxy_port(),
        })
        if not ok then
          assert.is_nil(err)
        end

        -- Then send using `request`, supplying a path and `Host` header instead of a
        -- full URI.
        local res, err = httpc:request({
            path = "/anthropic/llm/v1/chat/good",
            body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good-stream.json"),
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
        })
        if not res then
          assert.is_nil(err)
        end

        local reader = res.body_reader
        local buffer_size = 35536
        local events = {}
        local buf = require("string.buffer").new()

        -- extract event
        repeat
          -- receive next chunk
          local buffer, err = reader(buffer_size)
          if err then
            assert.is_falsy(err and err ~= "closed")
          end

          if buffer then
            -- we need to rip each message from this chunk
            for s in buffer:gmatch("[^\r\n]+") do
              local s_copy = s
              s_copy = string.sub(s_copy,7)
              s_copy = cjson.decode(s_copy)

              buf:put(s_copy
                    and s_copy.choices
                    and s_copy.choices
                    and s_copy.choices[1]
                    and s_copy.choices[1].delta
                    and s_copy.choices[1].delta.content
                    or "")
              table.insert(events, s)
            end
          end
        until not buffer

        assert.equal(#events, 8)
        assert.equal(buf:tostring(), "1 + 1 = 2")
        -- to verifiy not enable `kong.service.request.enable_buffering()`
        assert.logfile().has.no.line("/kong_buffered_http", true, 10)
      end)

      it("bad request is returned to the client not-streamed", function()
        local httpc = http.new()

        local ok, err, _ = httpc:connect({
          scheme = "http",
          host = helpers.mock_upstream_host,
          port = helpers.get_proxy_port(),
        })
        if not ok then
          assert.is_nil(err)
        end

        -- Then send using `request`, supplying a path and `Host` header instead of a
        -- full URI.
        local res, err = httpc:request({
            path = "/openai/llm/v1/chat/bad",
            body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good-stream.json"),
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
        })
        if not res then
          assert.is_nil(err)
        end

        local reader = res.body_reader
        local buffer_size = 35536
        local events = {}

        -- extract event
        repeat
          -- receive next chunk
          local buffer, err = reader(buffer_size)
          if err then
            assert.is_nil(err)
          end

          if buffer then
            -- we need to rip each message from this chunk
            for s in buffer:gmatch("[^\r\n]+") do
              table.insert(events, s)
            end
          end
        until not buffer

        assert.equal(#events, 1)
        assert.equal(res.status, 400)
        -- to verifiy not enable `kong.service.request.enable_buffering()`
        assert.logfile().has.no.line("/kong_buffered_http", true, 10)
      end)

    end)
  end)

end
