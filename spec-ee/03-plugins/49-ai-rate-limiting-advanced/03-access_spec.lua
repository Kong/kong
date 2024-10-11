-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"

local MOCK_PORT = helpers.get_available_port()
local PLUGIN_NAME = "ai-rate-limiting-advanced"

local SLEEP_TIME = 0.01
local MOCK_RATE = 3

local floor = math.floor
local time = ngx.time
local ngx_sleep = ngx.sleep
local update_time  = ngx.update_time
local ngx = ngx
local null = ngx.null

local fixtures_path = "spec-ee/fixtures/ai-rate-limiting-advanced";

-- all_strategries is not available on earlier versions spec.helpers in Kong
local strategies = helpers.all_strategies ~= nil and helpers.all_strategies or helpers.each_strategy

-- align the time to the begining of a fixed window
-- so that we are less likely to encounter a window reset
-- during the test
local function wait_for_next_fixed_window(window_size)
  local window_start = floor(time() / window_size) * window_size
  local window_elapsed_time = (time() - window_start)
  ngx_sleep(window_size - window_elapsed_time)
end


for _, strategy in strategies() do
  local policy = "local"

  local CONFIG_AI_PROXY = {
    route_type = "llm/v1/chat",
    logging = {
        log_payloads = false,
        log_statistics = true,
    },
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
            llama2_format = "openai",
            upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
        },
    },
   }

  local CONFIG_AI_PROXY_COST = {
    route_type = "llm/v1/chat",
    logging = {
        log_payloads = false,
        log_statistics = true,
    },
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
            llama2_format = "openai",
            upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
            input_cost = 20,
            output_cost = 10,
        },
    },
   }

   local CONFIG_AI_REQUEST_TRANSFORMER = {
        prompt = "test",
        llm = {
            route_type = "llm/v1/chat",
            logging = {
                log_payloads = false,
                log_statistics = false, -- should also work without login enable
            },
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
                    llama2_format = "openai",
                    upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/transform"
                },
            },
        },
    }

    local CONFIG_AI_RESPONSE_TRANSFORMER_OPENAI = {
        prompt = "test",
        llm = {
            route_type = "llm/v1/chat",
            logging = {
                log_payloads = false,
                log_statistics = true,
            },
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
                llama2_format = "openai",
                upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/instruction/openai"
              },
            },
        },
    }

    local CONFIG_AI_RESPONSE_TRANSFORMER_AZURE = {
        prompt = "test",
        llm = {
            route_type = "llm/v1/chat",
            logging = {
                log_payloads = false,
                log_statistics = false,  -- should also work without login enable,
            },
            auth = {
              header_name = "Authorization",
              header_value = "Bearer azure-key",
            },
            model = {
              name = "gpt-3.5-turbo",
              provider = "azure",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                azure_instance = "azure-openai-service",
                azure_deployment_id = "gpt-3-5-deployment",
                upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/instruction/azure"
              },
            },
        },
    }

  local base = "ai-rate-limiting-advanced [#"..strategy.."]"

  describe(base, function()
    local proxy_client

    lazy_setup(function()
    local bp = helpers.get_db_utils(strategy ~= "off" and strategy or nil,
                                nil,
                                {"ai-rate-limiting-advanced"})
      -- set up openai mock fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.openai = [[
        server {
            server_name openai;
            listen ]]..MOCK_PORT..[[;

            default_type 'application/json';


            location = "/llm/v1/chat/good" {
                content_by_lua_block {
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
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/responses/bad_request.json"))
                        else
                            ngx.status = 200
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/responses/good.json"))
                        end
                    else
                        ngx.status = 401
                        ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/responses/unauthorized.json"))
                    end
                }
            }

            location = "/llm/v1/chat/transform" {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "application/json"

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
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/cohere/responses/bad_request.json"))
                        else
                            ngx.status = 200
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/cohere/request-transformer/response-in-json.json"))
                        end
                    else
                        ngx.status = 401
                        ngx.print(pl_file.read("]] .. fixtures_path .. [[/cohere/responses/unauthorized.json"))
                    end
                }
            }

            location = "/llm/v1/chat/instruction/openai" {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "application/json"

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
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/responses/bad_request.json"))
                        else
                            ngx.status = 200
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/response-transformer/response-in-json.json"))
                        end
                    else
                        ngx.status = 401
                        ngx.print(pl_file.read("]] .. fixtures_path .. [[/openai/responses/unauthorized.json"))
                    end
                }
            }

            location = "/llm/v1/chat/instruction/azure" {
                content_by_lua_block {
                    ngx.header["Content-Type"] = "application/json"

                    local pl_file = require "pl.file"
                    local json = require("cjson.safe")
                    ngx.req.read_body()
                    local body, err = ngx.req.get_body_data()
                    body, err = json.decode(body)

                    local token = ngx.req.get_headers()["authorization"]
                    local token_query = ngx.req.get_uri_args()["apikey"]

                    if token == "Bearer azure-key" or token_query == "azure-key" or body.apikey == "azure-key" then
                        ngx.req.read_body()
                        local body, err = ngx.req.get_body_data()
                        body, err = json.decode(body)

                        if err or (body.messages == ngx.null) then
                            ngx.status = 400
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/azure/responses/bad_request.json"))
                        else
                            ngx.status = 200
                            ngx.print(pl_file.read("]] .. fixtures_path .. [[/azure/response-transformer/response-in-json.json"))
                        end
                    else
                        ngx.status = 401
                        ngx.print(pl_file.read("]] .. fixtures_path .. [[/azure/responses/unauthorized.json"))
                    end
                }
            }
        }
      ]]

      local empty_service = assert(bp.services:insert {
        name = "empty_service",
        host = "localhost", --helpers.mock_upstream_host,
        port = 8080, --MOCK_PORT,
        path = "/",
      })

      local consumer1 = assert(bp.consumers:insert {
        custom_id = "provider_123",
        username = "user123"
      })

      local consumer2 = assert(bp.consumers:insert {
        custom_id = "provider_456",
        username = "user456"
      })

      local consumer3 = assert(bp.consumers:insert {
        custom_id = "provider_789",
        username = "user789"
      })

      local consumer_group = assert(bp.consumer_groups:insert {
        name = "testGroup"
      })

      assert(bp.consumer_group_consumers:insert {
        consumer       = { id = consumer3.id },
        consumer_group = { id = consumer_group.id },
      })

      assert(bp.keyauth_credentials:insert {
        key = "apikey123",
        consumer = { id = consumer1.id },
      })

      assert(bp.keyauth_credentials:insert {
        key = "apikey456",
        consumer = { id = consumer2.id },
      })

      assert(bp.keyauth_credentials:insert {
        key = "apikey789",
        consumer = { id = consumer3.id },
      })

      local route1 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        name = "route-1",
        hosts = { "test1.com" },
      })

      local route2 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        name = "route-2",
        hosts = { "test2.com" },
      })

      -- without services
      local route3 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-3",
        hosts = { "test3.com" },
      })

      local route4 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        name = "route-4",
        hosts = { "test4.com" },
      })

      local route5 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        name = "route-5",
        hosts = { "test5.com" },
      })

      -- without services
      local route6 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-6",
        hosts = { "test6.com" },
      })

      -- with wrong type request prompt function
      local route7 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-7",
        hosts = { "test7.com" },
      })

      -- with error request prompt function
      local route8 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-8",
        hosts = { "test8.com" },
      })

      -- with error request prompt function
      local route9 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-9",
        hosts = { "test9.com" },
      })

      -- with error request prompt function
      local route10 = assert(bp.routes:insert {
        protocols = { "http" },
        name = "route-10",
        hosts = { "test10.com" },
      })

      assert(bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 310,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 2000,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 2,
            limit = 550,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 200,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 90,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 2,
            limit = 200,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route3.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 70,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 2,
            limit = 300,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 3,
            limit = 250,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route4.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE + 2,
            limit = 260,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 2000,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 3,
            limit = 550,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route5.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 100,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 90,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 2,
            limit = 100,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route6.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "azure",
            window_size = MOCK_RATE + 4,
            limit = 80,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 210,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 2,
            limit = 100,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route6.id },
        consumer_group = { id = consumer_group.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "azure",
            window_size = MOCK_RATE + 4,
            limit = 1000,
          },{
            name = "requestPrompt",
            window_size = MOCK_RATE + 1,
            limit = 2000,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 2,
            limit = 3000,
          }},
          request_prompt_count_function = "return 100", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or null),
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route7.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "requestPrompt",
            window_size = MOCK_RATE,
            limit = 100,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 1,
            limit = 200,
          }},
          request_prompt_count_function = "return \"hello\"", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or -1), -- test -1 value ok for local strategy
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route8.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "requestPrompt",
            window_size = MOCK_RATE,
            limit = 100,
          },{
            name = "cohere",
            window_size = MOCK_RATE + 1,
            limit = 200,
          }},
          request_prompt_count_function = "return #kong.request.get_raw_body_wrong()", -- check #kong.request.get_raw_body()
          sync_rate = (policy ~= "local" and 1 or -1), -- test -1 value ok for local strategy
          window_type = "fixed",
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route9.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 100,
          }},
          sync_rate = (policy ~= "local" and 1 or -1), -- test -1 value ok for local strategy
          window_type = "fixed",
          tokens_count_strategy = "completion_tokens"
          -- disable_penalty = false,
        }
      })

      assert(bp.plugins:insert {
        name = "ai-rate-limiting-advanced",
        route = { id = route10.id },
        config = {
          strategy = policy,
          llm_providers = {{
            name = "openai",
            window_size = MOCK_RATE,
            limit = 0.0025,
          }},
          sync_rate = (policy ~= "local" and 1 or -1), -- test -1 value ok for local strategy
          window_type = "fixed",
          tokens_count_strategy = "cost"
          -- disable_penalty = false,
        }
      })

      -- route 1 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route1.id },
        config = CONFIG_AI_PROXY
      })

      -- route 2 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route2.id },
        config = CONFIG_AI_PROXY
      })

      -- route 3 plugins
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route3.id },
      })

      assert(bp.plugins:insert {
        name = "ai-request-transformer",
        route = { id = route3.id },
        config = CONFIG_AI_REQUEST_TRANSFORMER
      })

      assert(bp.plugins:insert {
        name = "ai-response-transformer",
        route = { id = route3.id },
        config = CONFIG_AI_RESPONSE_TRANSFORMER_OPENAI
      })

      -- route 4 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route4.id },
        config = CONFIG_AI_PROXY
      })

      -- route 5 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route5.id },
        config = CONFIG_AI_PROXY
      })

      -- route 6 plugins
      assert(bp.plugins:insert {
        name = "key-auth",
        route = { id = route6.id },
      })

      assert(bp.plugins:insert {
        name = "ai-request-transformer",
        route = { id = route6.id },
        config = CONFIG_AI_REQUEST_TRANSFORMER
      })

      assert(bp.plugins:insert {
        name = "ai-response-transformer",
        route = { id = route6.id },
        config = CONFIG_AI_RESPONSE_TRANSFORMER_AZURE
      })

      -- route 7 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route7.id },
        config = CONFIG_AI_PROXY
      })

      -- route 8 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route8.id },
        config = CONFIG_AI_PROXY
      })

      -- route 9 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route9.id },
        config = CONFIG_AI_PROXY
      })

      -- route 10 plugins
      assert(bp.plugins:insert {
        name = "ai-proxy",
        route = { id = route10.id },
        config = CONFIG_AI_PROXY_COST
      })

      assert(helpers.start_kong({
        plugins = "ai-rate-limiting-advanced,ai-proxy,ai-request-transformer,ai-response-transformer,key-auth",
        nginx_conf = "spec/fixtures/custom_nginx.template",
        database   = strategy,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }, nil, nil, fixtures))

    end)

    lazy_teardown(function()
        helpers.stop_kong(nil, true)
    end)

    before_each(function()
      proxy_client = helpers.proxy_client()
      update_time()
    end)

    after_each(function()
      if proxy_client then proxy_client:close() end
      ngx_sleep(SLEEP_TIME)
    end)

    describe("openai general sliding window", function()
        it("check limit ok", function()
            for i = 1, 7 do
                proxy_client = helpers.proxy_client()
                local res = assert(proxy_client:send {
                method = "POST",
                path = "/post",
                headers = {
                    ["Host"] = "test1.com",
                    ["Content-Type"] = "application/json",
                    ["accept"] = "application/json",
                },
                body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
                })

                assert.res_status(200, res)

                assert.are.same(310, tonumber(res.headers["x-ai-ratelimit-limit-3-openai"]))
                assert.are.same(2000, tonumber(res.headers["x-ai-ratelimit-limit-4-requestprompt"]))
                assert.are.same(100, tonumber(res.headers["x-ai-ratelimit-query-cost-4-requestprompt"]))
                assert.are.same(310 - ((i-1) * 50), tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
                assert.are.same(550, tonumber(res.headers["x-ai-ratelimit-remaining-5-cohere"]))
                assert.are.same(2000 - (i * 100), tonumber(res.headers["x-ai-ratelimit-remaining-4-requestprompt"]))
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-reset"])
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-after"])
            end
        end)

        it("check limit with tokens for openai", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test1.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): openai" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0)
            assert.is_true(retry_after <= 8) -- Few more seconds as using sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-3-openai"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-3-openai"]))
        end)

        it("check limit with tokens for requestPrompt", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test2.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): requestPrompt" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0)
            assert.is_true(retry_after <= 9) -- Few more seconds as using sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-4-requestPrompt"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-4-requestPrompt"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-4-requestPrompt"]))
        end)

        it("check response 200 for user 123", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey123",
            headers = {
                ["Host"] = "test3.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)
        end)

        it("check limit for user 123 with tokens for all openai and azure", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey123",
            headers = {
                ["Host"] = "test3.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): openai" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0)
            assert.is_true(retry_after <= 8) -- Few more seconds as using sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
        end)


        it("check response 200 for user 456", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey456",
            headers = {
                ["Host"] = "test3.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)
        end)

        it("check response 200 after 8s", function()
            ngx_sleep(8)
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey123",
            headers = {
                ["Host"] = "test3.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)
        end)
    end)

    describe("openai general fixed window", function()
        it("check limit ok", function()
            local window_size =  MOCK_RATE + 2
            wait_for_next_fixed_window(window_size)
            for i = 1, 6 do
                proxy_client = helpers.proxy_client()
                local res = assert(proxy_client:send {
                method = "POST",
                path = "/post",
                headers = {
                    ["Host"] = "test4.com",
                    ["Content-Type"] = "application/json",
                    ["accept"] = "application/json",
                },
                body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
                })

                assert.res_status(200, res)

                assert.are.same(260, tonumber(res.headers["x-ai-ratelimit-limit-5-openai"]))
                assert.are.same(2000, tonumber(res.headers["x-ai-ratelimit-limit-4-requestprompt"]))
                assert.are.same(550, tonumber(res.headers["x-ai-ratelimit-limit-6-cohere"]))
                assert.are.same(550, tonumber(res.headers["x-ai-ratelimit-remaining-6-cohere"]))
                assert.are.same(100, tonumber(res.headers["x-ai-ratelimit-query-cost-4-requestprompt"]))
                assert.are.same(260 - ((i-1) * 50), tonumber(res.headers["x-ai-ratelimit-remaining-5-openai"]))
                assert.are.same(2000 - (i * 100), tonumber(res.headers["x-ai-ratelimit-remaining-4-requestprompt"]))
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-reset"])
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-after"])
            end
        end)

        it("check limit with tokens for openai", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test4.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },

            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): openai" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0) -- Uses sliding window and is executed in quick succession
            assert.is_true(retry_after <= 10) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-5-openai"]))
            assert.are.same(550, tonumber(res.headers["x-ai-ratelimit-remaining-6-cohere"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-5-openai"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-5-openai"]))
        end)

        it("check response 200", function()
            local window_size = MOCK_RATE + 2
            wait_for_next_fixed_window(window_size)
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test4.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)
        end)

        it("check limit with tokens for requestPrompt", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test5.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): requestPrompt" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0) -- Uses sliding window and is executed in quick succession
            assert.is_true(retry_after <= 9) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-4-requestPrompt"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-4-requestPrompt"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-4-requestPrompt"]))
        end)

        it("check response 200 for user 123", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey123",
            headers = {
                ["Host"] = "test6.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)
        end)

        it("check limit for user 123 with tokens for all openai and azure", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey123",
            headers = {
                ["Host"] = "test6.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): azure, cohere" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0) -- Uses sliding window and is executed in quick succession
            assert.is_true(retry_after <= 9) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-7-azure"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-5-cohere"]))
        end)

        it("check response 200 for user 456 with service config", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey456",
            headers = {
                ["Host"] = "test6.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)

            assert.are.same(100, tonumber(res.headers["x-ai-ratelimit-limit-5-cohere"]))
            assert.are.same(10, tonumber(res.headers["x-ai-ratelimit-remaining-5-cohere"]))
            assert.are.same(80, tonumber(res.headers["x-ai-ratelimit-limit-7-azure"]))
            assert.are.same(10, tonumber(res.headers["x-ai-ratelimit-remaining-7-azure"]))
        end)

        it("check response 200 for user 789 with consumer group config", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post?apikey=apikey789",
            headers = {
                ["Host"] = "test6.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            assert.res_status(200, res)

            assert.are.same(3000, tonumber(res.headers["x-ai-ratelimit-limit-5-cohere"]))
            assert.are.same(2910, tonumber(res.headers["x-ai-ratelimit-remaining-5-cohere"]))
            assert.are.same(1000, tonumber(res.headers["x-ai-ratelimit-limit-7-azure"]))
            assert.are.same(930, tonumber(res.headers["x-ai-ratelimit-remaining-7-azure"]))
        end)

        it("failing if requestPrompt function not returning a number", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test7.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(500, res)
            local json = cjson.decode(body)

            assert.same({ message = "Bad return value from the request prompt count function" }, json)
            assert.logfile().has.line("Bad return value from function, expected number type, got string", true, 0.1)
        end)

        it("failing if requestPrompt function returning an error", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test8.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(500, res)
            local json = cjson.decode(body)

            assert.same({ message = "Error executing request prompt count function" }, json)

            assert.logfile().has.line("Error executing request prompt count function", true, 0.1)
            assert.logfile().has.line("attempt to call field 'get_raw_body_wrong' (a nil value)", true, 0.1)
        end)

        it("check limit ok for completion tokens", function()
            for i = 1, 4 do
                proxy_client = helpers.proxy_client()
                local res = assert(proxy_client:send {
                method = "POST",
                path = "/post",
                headers = {
                    ["Host"] = "test9.com",
                    ["Content-Type"] = "application/json",
                    ["accept"] = "application/json",
                },
                body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
                })

                assert.res_status(200, res)

                assert.are.same(100, tonumber(res.headers["x-ai-ratelimit-limit-3-openai"]))
                assert.are.same(100 - ((i-1) * 30), tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-reset"])
                assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-after"])
            end
        end)

        it("check limit with completion tokens for openai", function()
            -- Additonal request, while limit is 6/window
            proxy_client = helpers.proxy_client()
            local res = assert(proxy_client:send {
            method = "POST",
            path = "/post",
            headers = {
                ["Host"] = "test9.com",
                ["Content-Type"] = "application/json",
                ["accept"] = "application/json",
            },
            body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
            })

            local body = assert.res_status(429, res)
            local json = cjson.decode(body)

            assert.same({ message = "AI token rate limit exceeded for provider(s): openai" }, json)
            local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
            assert.is_true(retry_after > 0) -- Uses sliding window and is executed in quick succession
            assert.is_true(retry_after <= 10) -- Uses sliding window and is executed in quick succession
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
            assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-3-openai"]))
            assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-3-openai"]))
        end)

        it("check limit ok for cost strategy", function()
          for i = 1, 4 do
              proxy_client = helpers.proxy_client()
              local res = assert(proxy_client:send {
              method = "POST",
              path = "/post",
              headers = {
                  ["Host"] = "test10.com",
                  ["Content-Type"] = "application/json",
                  ["accept"] = "application/json",
              },
              body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
              })

              assert.res_status(200, res)

              -- Use to handle small round numbers
              local passed_value_1 = string.format("%.5g", res.headers["x-ai-ratelimit-limit-3-openai"])
              local passed_value_2 = string.format("%.5g", res.headers["x-ai-ratelimit-remaining-3-openai"])
              local expected_value_1 = string.format("%.5g", 0.0025)
              local expected_value_2 = string.format("%.5g", 0.0025 - ((i-1) * 0.0007))

              assert.are.same(expected_value_1, passed_value_1)
              assert.are.same(expected_value_2, passed_value_2)
              assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-reset"])
              assert.is_nil(res.headers["x-ai-ratelimitbysize-retry-after"])
          end
        end)

        it("check limit with cost for openai", function()
          -- Additonal request, while limit is 6/window
          proxy_client = helpers.proxy_client()
          local res = assert(proxy_client:send {
          method = "POST",
          path = "/post",
          headers = {
              ["Host"] = "test10.com",
              ["Content-Type"] = "application/json",
              ["accept"] = "application/json",
          },
          body = pl_file.read(fixtures_path .. "/openai/requests/good.json")
          })

          local body = assert.res_status(429, res)
          local json = cjson.decode(body)

          assert.same({ message = "AI token rate limit exceeded for provider(s): openai" }, json)
          local retry_after = tonumber(res.headers["x-ai-ratelimit-retry-after"])
          assert.is_true(retry_after > 0) -- Uses sliding window and is executed in quick succession
          assert.is_true(retry_after <= 10) -- Uses sliding window and is executed in quick succession
          assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset"]))
          assert.are.same(0, tonumber(res.headers["x-ai-ratelimit-remaining-3-openai"]))
          assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-reset-3-openai"]))
          assert.same(retry_after, tonumber(res.headers["x-ai-ratelimit-retry-after-3-openai"]))
      end)
    end)
  end)
end
