local helpers = require("spec.helpers")
local cjson = require("cjson")
local pl_file = require("pl.file")
local strip = require("kong.tools.string").strip

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

local FILE_LOG_PATH_WITH_PAYLOADS = os.tmpname()

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

local _EXPECTED_CHAT_STATS = {
  meta = {
    plugin_id = '17434c15-2c7c-4c2f-b87a-58880533a3c1',
    provider_name = 'gemini',
    request_model = 'gemini-1.5-pro',
    response_model = 'gemini-1.5-pro',
    llm_latency = 1,
  },
  usage = {
    prompt_tokens = 2,
    completion_tokens = 11,
    total_tokens = 13,
    time_per_token = 1,
    cost = 0.000195,
  },
}

for _, strategy in helpers.all_strategies() do
  if strategy ~= "cassandra" then
    describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
      local client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

        -- set up gemini mock fixtures
        local fixtures = {
          http_mock = {},
        }

        fixtures.http_mock.gemini = [[
          server {
            server_name gemini;
            listen ]] .. MOCK_PORT .. [[;
            
            default_type 'application/json';

            location = "/v1/chat/completions" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                local token = ngx.req.get_headers()["authorization"]
                if token == "Bearer gemini-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)
                  
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/gemini/llm-v1-chat/responses/good.json"))
                end
              }
            }
          }
        ]]

        local empty_service = assert(bp.services:insert({
          name = "empty_service",
          host = "localhost", --helpers.mock_upstream_host,
          port = 8080, --MOCK_PORT,
          path = "/",
        }))

        -- 200 chat good with one option
        local chat_good = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/gemini/llm/v1/chat/good" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          id = "17434c15-2c7c-4c2f-b87a-58880533a3c1",
          route = { id = chat_good.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "Authorization",
              header_value = "Bearer gemini-key",
            },
            logging = {
              log_payloads = true,
              log_statistics = true,
            },
            model = {
              name = "gemini-1.5-pro",
              provider = "gemini",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT .. "/v1/chat/completions",
                input_cost = 15.0,
                output_cost = 15.0,
              },
            },
          },
        })
        bp.plugins:insert {
          name = "file-log",
          route = { id = chat_good.id },
          config = {
            path = FILE_LOG_PATH_WITH_PAYLOADS,
          },
        }

        -- start kong
        assert(helpers.start_kong({
          -- set the strategy
          database = strategy,
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
        if client then
          client:close()
        end
      end)

      describe("gemini llm/v1/chat", function()
        it("good request", function()
          local r = client:get("/gemini/llm/v1/chat/good", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
          })
          -- validate that the request succeeded, response status 200
          local body = assert.res_status(200, r)
          local json = cjson.decode(body)

          -- check this is in the 'kong' response format
          assert.equals(json.model, "gemini-1.5-pro")
          assert.equals(json.object, "chat.completion")
          assert.equals(json.choices[1].finish_reason, "stop")

          assert.is_table(json.choices)
          assert.is_string(json.choices[1].message.content)
          assert.same("Everything is okay.", json.choices[1].message.content)

          -- test stats from file-log
          local log_message = wait_for_json_log_entry(FILE_LOG_PATH_WITH_PAYLOADS)
          assert.same("127.0.0.1", log_message.client_ip)
          assert.is_number(log_message.request.size)
          assert.is_number(log_message.response.size)
  
          local actual_stats = log_message.ai.proxy

          local actual_llm_latency = actual_stats.meta.llm_latency
          local actual_time_per_token = actual_stats.usage.time_per_token
          local time_per_token = actual_llm_latency / actual_stats.usage.completion_tokens
          
          local actual_request_log = actual_stats.payload.request
          local actual_response_log = actual_stats.payload.response
          actual_stats.payload = nil

          actual_stats.meta.llm_latency = 1
          actual_stats.usage.time_per_token = 1
  
          assert.same(_EXPECTED_CHAT_STATS, actual_stats)
          assert.is_true(actual_llm_latency >= 0)
          assert.same(tonumber(string.format("%.3f", actual_time_per_token)), tonumber(string.format("%.3f", time_per_token)))
          assert.match_re(actual_request_log, [[.*contents.*What is 1 \+ 1.*]])
          assert.match_re(actual_response_log, [[.*content.*Everything is okay.*]])
        end)
      end)
    end)
  end
end