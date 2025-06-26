local helpers = require("spec.helpers")
local cjson = require("cjson")
local pl_file = require("pl.file")
local strip = require("kong.tools.string").strip

local PLUGIN_NAME = "ai-proxy"

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

local _EXPECTED_CHAT_STATS_GEMINI = {
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
  local gemini_driver

  if strategy ~= "cassandra" then
    describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
      local client
      local MOCK_PORTS = {
        _GEMINI = 0,
        _ANTHROPIC = 0,
      }

      lazy_setup(function()
        _G._TEST = true
        package.loaded["kong.llm.drivers.gemini"] = nil
        gemini_driver = require("kong.llm.drivers.gemini")
        
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })
        
        -- set up gemini mock fixtures
        local fixtures = {
          http_mock = {},
        }

        local GEMINI_MOCK = pl_file.read("spec/fixtures/ai-proxy/mock_servers/gemini.lua.txt")
        MOCK_PORTS._GEMINI = helpers.get_available_port()
        fixtures.http_mock.gemini = string.format(GEMINI_MOCK, MOCK_PORTS._GEMINI)

        local ANTHROPIC_MOCK = pl_file.read("spec/fixtures/ai-proxy/mock_servers/anthropic.lua.txt")
        MOCK_PORTS._ANTHROPIC = helpers.get_available_port()
        fixtures.http_mock.anthropic = string.format(ANTHROPIC_MOCK, MOCK_PORTS._ANTHROPIC)

        local empty_service = assert(bp.services:insert({
          name = "empty_service",
          host = "localhost", --helpers.mock_upstream_host,
          port = 8080, --MOCK_PORTS._GEMINI,
          path = "/",
        }))

        ----
        -- GEMINI MODELS
        ----
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
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORTS._GEMINI .. "/v1/chat/completions",
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

        -- 200 chat good with variable
        local chat_good_with_var = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "~/gemini/llm/v1/chat/good/(?<model>[^/]+)" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = chat_good_with_var.id },
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
              name = "$(uri_captures.model)",
              provider = "gemini",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORTS._GEMINI .. "/v1/embeddings",
                input_cost = 15.0,
                output_cost = 15.0,
              },
            },
          },
        })
        bp.plugins:insert {
          name = "file-log",
          route = { id = chat_good_with_var.id },
          config = {
            path = FILE_LOG_PATH_WITH_PAYLOADS,
          },
        }

        -- 200 chat good with query param auth using ai-proxy-advanced and ai-response-transformer
        local chat_query_auth = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/gemini/llm/v1/chat/query-auth" },
        }))
        bp.plugins:insert({
          name = "ai-proxy-advanced",
          id = "27544c15-3c8c-5c3f-c98a-69990644a4d2",
          route = { id = chat_query_auth.id },
          config = {
            targets = {
              {
                route_type = "llm/v1/chat",
                auth = {
                  param_name = "key",
                  param_value = "gemini-query-key",
                  param_location = "query",
                },
                logging = {
                  log_payloads = true,
                  log_statistics = true,
                },
                model = {
                  name = "gemini-1.5-flash",
                  provider = "gemini",
                  options = {
                    max_tokens = 256,
                    temperature = 1.0,
                    upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORTS._GEMINI .. "/v1/chat/completions/query-auth",
                    input_cost = 15.0,
                    output_cost = 15.0,
                  },
                },
              },
            },
          },
        })
        bp.plugins:insert({
          name = "ai-response-transformer",
          id = "37655d26-4d9d-6d4f-d09b-70001755b5e3",
          route = { id = chat_query_auth.id },
          config = {
            prompt = "Mask all emails and phone numbers in my JSON message with '*'. Return me ONLY the resulting JSON.",
            parse_llm_response_json_instructions = false,
            llm = {
              route_type = "llm/v1/chat",
              auth = {
                param_name = "key",
                param_value = "gemini-query-key",
                param_location = "query",
              },
              logging = {
                log_payloads = true,
                log_statistics = true,
              },
              model = {
                provider = "gemini",
                name = "gemini-1.5-flash",
                options = {
                  upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORTS._GEMINI .. "/v1/chat/completions/query-auth",
                  input_cost = 15.0,
                  output_cost = 15.0,
                },
              },
            },
          },
        })
        bp.plugins:insert {
          name = "file-log",
          route = { id = chat_query_auth.id },
          config = {
            path = FILE_LOG_PATH_WITH_PAYLOADS,
          },
        }

        ----
        -- ANTHROPIC MODELS
        ----
        local chat_good_anthropic = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/anthropic/llm/v1/chat/good" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          id = "17434c15-2c7c-4c2f-b87a-58880533a3c2",
          route = { id = chat_good_anthropic.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "x-api-key",
              header_value = "anthropic-key",
            },
            logging = {
              log_payloads = true,
              log_statistics = true,
            },
            model = {
              name = "claude-2.1",
              provider = "gemini",
              options = {
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORTS._ANTHROPIC .. "/llm/v1/chat/good",
                input_cost = 15.0,
                output_cost = 15.0,
              },
            },
          },
        })
        bp.plugins:insert {
          name = "file-log",
          route = { id = chat_good_anthropic.id },
          config = {
            path = FILE_LOG_PATH_WITH_PAYLOADS,
          },
        }

        -- TODO: mock gcp client to test vertex mode

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

      describe("gemini models", function()
        describe("gemini (gemini) llm/v1/chat", function()
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
    
            assert.same(_EXPECTED_CHAT_STATS_GEMINI, actual_stats)
            assert.is_true(actual_llm_latency >= 0)
            assert.same(tonumber(string.format("%.3f", actual_time_per_token)), tonumber(string.format("%.3f", time_per_token)))
            assert.match_re(actual_request_log, [[.*content.*What is 1 \+ 1.*]])
            assert.match_re(actual_response_log, [[.*content.*Everything is okay.*]])
          end)
        end)

        describe("gemini (gemini) #llm/v1/embeddings", function()
          it("good request", function()
            local r = client:get("/gemini/llm/v1/embeddings/good", {
              headers = {
                ["content-type"] = "application/json",
                ["accept"] = "application/json",
              },
              body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-embeddings/requests/good.json"),
            })
            -- validate that the request succeeded, response status 200
            local body = assert.res_status(200, r)
            local json = cjson.decode(body)

            -- check this is in the 'kong' response format
          -- check this is in the 'kong' response format
          assert.equals(json.object, "list")
          assert.not_nil(json.data and json.data[1])
          assert.equals(json.data[1].object, "embedding")
          assert.equals(json.data[1].index, 0)
          assert.not_nil(json.data[1].embedding)
          assert.same(json.usage and json.usage.total_tokens, 0) -- gemini non-vertex api doesn't return this 
          assert.same(json.usage and json.usage.prompt_tokens, 0) -- gemini non-vertex api doesn't return this 
          assert.equals("gemini-embedding-exp-03-07", json.model)
          assert.equals("gemini/gemini-embedding-exp-03-07", r.headers["X-Kong-LLM-Model"])

          local log_message = wait_for_json_log_entry(FILE_LOG_PATH_WITH_PAYLOADS)
          assert.same("127.0.0.1", log_message.client_ip)
          assert.is_number(log_message.request.size)
          assert.is_number(log_message.response.size)

          -- test ai-proxy or ai-proxy-advanced stats (both in log_message.ai.proxy namespace)
          local _, first_got = next(log_message.ai)

          first_got.meta.llm_latency = 1
          first_got.meta.plugin_id = "e126e5bb-0f66-49f4-bba0-ede6152a92b4"
          first_got.payload = nil -- skip testing this

          assert.same({
            meta = {
              llm_latency = 1,
              plugin_id = "e126e5bb-0f66-49f4-bba0-ede6152a92b4",
              provider_name = "gemini",
              request_model = "gemini-embedding-exp-03-07",
              response_model = "gemini-embedding-exp-03-07"
            },
            usage = {
              completion_tokens = 0,
              cost = 0,
              prompt_tokens = 0, -- gemini non-vertex api doesn't return this
              time_per_token = 0,
              total_tokens = 0 -- gemini non-vertex api doesn't return this
            }
          }, first_got)
          end)
        end)

        describe("gemini (gemini) llm/v1/chat with query param auth", function()
          it("good request with query parameter authentication", function()
            local r = client:get("/gemini/llm/v1/chat/query-auth", {
              headers = {
                ["content-type"] = "application/json",
                ["accept"] = "application/json",
              },
              body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
            })
            -- validate that the request succeeded, response status 200
            local body = assert.res_status(200, r)
            assert.same("Everything is okay.", body)
          end)
        end)
      end)

      describe("anthropic models", function()
        describe("gemini (anthropic) llm/v1/chat", function()
          it("good request", function()
            local r = client:get("/anthropic/llm/v1/chat/good", {
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
            assert.equals(json.model, "claude-2.1")
            assert.equals(json.object, "chat.completion")
            assert.equals(json.choices[1].finish_reason, "stop")

            assert.is_table(json.choices)
            assert.is_string(json.choices[1].message.content)
            assert.same("The sum of 1 + 1 is 2.", json.choices[1].message.content)

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
    
            assert.is_true(actual_llm_latency >= 0)
            assert.same(tonumber(string.format("%.3f", actual_time_per_token)), tonumber(string.format("%.3f", time_per_token)))
            assert.match_re(actual_request_log, [[.*messages.*What is 1 \+ 1.*]])
            assert.match_re(actual_response_log, [[.*content.*The sum of 1 \+ 1 is 2.*]])
          end)
        end)
      end)

      describe("#utilities", function()

        it("should parse gemini model names into coordinates", function()
          -- gemini no stream
          local model_name = "gemini-1.5-pro"
          local coordinates = gemini_driver._get_model_coordinates(model_name, false)

          assert.same({
            publisher = "google",
            operation = "generateContent",
          }, coordinates)

          -- gemini stream
          model_name = "gemini-1.5-pro"
          coordinates = gemini_driver._get_model_coordinates(model_name, true)
          assert.same({
            publisher = "google",
            operation = "streamGenerateContent",
          }, coordinates)

          -- claude no stream
          model_name = "claude-3.5-sonnet-20240229"
          coordinates = gemini_driver._get_model_coordinates(model_name, false)
          assert.same({
            publisher = "anthropic",
            operation = "rawPredict",
          }, coordinates)

          -- claude stream
          model_name = "claude-3.5-sonnet-20240229"
          coordinates = gemini_driver._get_model_coordinates(model_name, true)
          assert.same({
            publisher = "anthropic",
            operation = "streamRawPredict",
          }, coordinates)

          -- ai21/jamba
          model_name = "jamba-1.0"
          coordinates = gemini_driver._get_model_coordinates(model_name, false)
          assert.same({
            publisher = "ai21",
            operation = "rawPredict",
          }, coordinates)

          -- mistral
          model_name = "mistral-large-2407"
          coordinates = gemini_driver._get_model_coordinates(model_name, false)
          assert.same({
            publisher = "mistral",
            operation = "rawPredict",
          }, coordinates)

          -- non-text model
          model_name = "text-embedding-004"
          coordinates = gemini_driver._get_model_coordinates(model_name, false)
          assert.same({
            publisher = "google",
            operation = "generateContent", -- doesn't matter, not used
          }, coordinates)

          model_name = "imagen-4.0-generate-preview-06-06"
          coordinates = gemini_driver._get_model_coordinates(model_name, false)
          assert.same({
            publisher = "google",
            operation = "generateContent", -- doesn't matter, not used
          }, coordinates)

        end)

        it("should provide correct gemini (vertex) URL pattern", function()
          -- err
          local _, err = gemini_driver._get_gemini_vertex_url({
            provider = "gemini",
            name = "gemini-1.5-pro",
          }, "llm/v1/chat", false)

          assert.equals("model.options.gemini.* options must be set for vertex mode", err)

          local gemini_options = {
              gemini = {
                api_endpoint = "gemini.local",
                project_id = "test-project",
                location_id = "us-central1",
              },
            }

          -- gemini no stream
          local url = gemini_driver._get_gemini_vertex_url({
            provider = "gemini",
            name = "gemini-1.5-pro",
            options = gemini_options,
          }, "llm/v1/chat", false)

          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/google/models/gemini-1.5-pro:generateContent", url)

          -- gemini stream
          url = gemini_driver._get_gemini_vertex_url({
            provider = "gemini",
            name = "gemini-1.5-pro",
            options = gemini_options,
          }, "llm/v1/chat", true)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/google/models/gemini-1.5-pro:streamGenerateContent", url)

          -- claude no stream
          url = gemini_driver._get_gemini_vertex_url({
            provider = "anthropic",
            name = "claude-3.5-sonnet-20240229",
            options = gemini_options,
          }, "llm/v1/chat", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/anthropic/models/claude-3.5-sonnet-20240229:rawPredict", url)

          -- claude stream
          url = gemini_driver._get_gemini_vertex_url({
            provider = "anthropic",
            name = "claude-3.5-sonnet-20240229",
            options = {
              gemini = {
                api_endpoint = "gemini.local",
                project_id = "test-project",
                location_id = "us-central1",
              },
            },
          }, "llm/v1/chat", true)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/anthropic/models/claude-3.5-sonnet-20240229:streamRawPredict", url)

          -- ai21/jamba
          url = gemini_driver._get_gemini_vertex_url({
            provider = "ai21",
            name = "jamba-1.0",
            options = gemini_options,
          }, "llm/v1/chat", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/ai21/models/jamba-1.0:rawPredict", url)

          -- mistral
          url = gemini_driver._get_gemini_vertex_url({
            provider = "mistral",
            name = "mistral-large-2407",
            options = gemini_options,
          }, "llm/v1/chat", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/mistral/models/mistral-large-2407:rawPredict", url)

          -- non-text model
          url = gemini_driver._get_gemini_vertex_url({
            provider = "google",
            name = "text-embedding-004",
            options = gemini_options,
          }, "llm/v1/embeddings", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/google/models/text-embedding-004:predict", url)

          url = gemini_driver._get_gemini_vertex_url({
            provider = "google",
            name = "imagen-4.0-generate-preview-06-06",
            options = gemini_options,
          }, "image/v1/images/generations", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/google/models/imagen-4.0-generate-preview-06-06:generateContent", url)

          url = gemini_driver._get_gemini_vertex_url({
            provider = "google",
            name = "imagen-4.0-generate-preview-06-06",
            options = gemini_options,
          }, "image/v1/images/edits", false)
          assert.equals("https://gemini.local/v1/projects/test-project/locations/us-central1/publishers/google/models/imagen-4.0-generate-preview-06-06:generateContent", url)

        end)

        it("should detect vertex mode automatically", function()
          local model = {
            name = "gemini-1.5-pro",
            options = {
              gemini = {
                api_endpoint = "gemini.local",
                project_id = "test-project",
                location_id = "us-central1",
              },
            },
          }

          assert.is_true(gemini_driver._is_vertex_mode(model))

          model = {
            name = "gemini-1.5-pro",
          }

          assert.is_falsy(gemini_driver._is_vertex_mode(model))
        end)
      end)
    end)
  end
end
