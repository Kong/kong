local helpers = require("spec.helpers")
local cjson = require("cjson")
local pl_file = require("pl.file")
local inspect = require("inspect")

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

for _, strategy in helpers.all_strategies() do
  if strategy ~= "cassandra" then
    describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
      local client

      lazy_setup(function()
        local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

        -- set up huggingface mock fixtures
        local fixtures = {
          http_mock = {},
        }

        fixtures.http_mock.huggingface = [[
        server {
          server_name huggingface;
          listen ]] .. MOCK_PORT .. [[;
          
          default_type 'application/json';

          location = "/v1/chat/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer huggingface-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)
                
                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          # completions is on the root of huggingface models
          location = "/" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer huggingface-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)
                
                if err or (body.prompt == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-completions/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-completions/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-completions/responses/unauthorized.json"))
              end
            }
          }
          location = "/model-loading/v1/chat/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
                
              ngx.status = 503
              ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/responses/bad_response_model_load.json"))
            }
          }
          location = "/model-timeout/v1/chat/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
                
              ngx.status = 504
              ngx.print(pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/responses/bad_response_timeout.json"))
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
          paths = { "/huggingface/llm/v1/chat/good" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = chat_good.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "Authorization",
              header_value = "Bearer huggingface-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = true,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT,
              },
            },
          },
        })
        local completions_good = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/huggingface/llm/v1/completions/good" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = completions_good.id },
          config = {
            route_type = "llm/v1/completions",
            auth = {
              header_name = "Authorization",
              header_value = "Bearer huggingface-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = true,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT,
              },
            },
          },
        })
        -- 401 unauthorized
        local chat_401 = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/huggingface/llm/v1/chat/unauthorized" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = chat_401.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "api-key",
              header_value = "wrong-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = true,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT,
              },
            },
          },
        })
        -- 401 unauthorized
        local completions_401 = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/huggingface/llm/v1/completions/unauthorized" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = completions_401.id },
          config = {
            route_type = "llm/v1/completions",
            auth = {
              header_name = "api-key",
              header_value = "wrong-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = true,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT,
              },
            },
          },
        })
        -- 503 Service Temporarily Unavailable
        local chat_503 = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/huggingface/llm/v1/chat/bad-response/model-loading" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = chat_503.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "api-key",
              header_value = "huggingface-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = false,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT.."/model-loading",
              },
            },
          },
        })
        -- 503 Service Timeout
        local chat_503_to = assert(bp.routes:insert({
          service = empty_service,
          protocols = { "http" },
          strip_path = true,
          paths = { "/huggingface/llm/v1/chat/bad-response/model-timeout" },
        }))
        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = chat_503_to.id },
          config = {
            route_type = "llm/v1/chat",
            auth = {
              header_name = "api-key",
              header_value = "huggingface-key",
            },
            model = {
              name = "mistralai/Mistral-7B-Instruct-v0.2",
              provider = "huggingface",
              options = {
                max_tokens = 256,
                temperature = 1.0,
                huggingface = {
                  use_cache = false,
                  wait_for_model = false,
                },
                upstream_url = "http://" .. helpers.mock_upstream_host .. ":" .. MOCK_PORT.."/model-timeout",
              },
            },
          },
        })

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
      end)

      before_each(function()
        client = helpers.proxy_client()
      end)

      after_each(function()
        if client then
          client:close()
        end
      end)

      describe("huggingface llm/v1/chat", function()
        it("good request", function()
          local r = client:get("/huggingface/llm/v1/chat/good", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/requests/good.json"),
          })
          -- validate that the request succeeded, response status 200
          local body = assert.res_status(200, r)
          local json = cjson.decode(body)

          -- check this is in the 'kong' response format
          assert.equals(json.model, "mistralai/Mistral-7B-Instruct-v0.2")
          assert.equals(json.object, "chat.completion")

          assert.is_table(json.choices)
          --print("json: ", inspect(json))
          assert.is_string(json.choices[1].message.content)
          assert.same(
            " The sum of 1 + 1 is 2. This is a basic arithmetic operation and the answer is always the same: adding one to one results in having two in total.",
            json.choices[1].message.content
          )
        end)
      end)
      describe("huggingface llm/v1/completions", function()
        it("good request", function()
          local r = client:get("/huggingface/llm/v1/completions/good", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-completions/requests/good.json"),
          })

          -- validate that the request succeeded, response status 200
          local body = assert.res_status(200, r)
          local json = cjson.decode(body)

          -- check this is in the 'kong' response format
          assert.equals("mistralai/Mistral-7B-Instruct-v0.2", json.model)
          assert.equals("llm/v1/completions", json.object)

          assert.is_table(json.choices)
          assert.is_table(json.choices[1])
          assert.same("I am a language model AI created by Mistral AI", json.choices[1].message.content)
        end)
      end)
      describe("huggingface no auth", function()
        it("unauthorized request chat", function()
          local r = client:get("/huggingface/llm/v1/chat/unauthorized", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/requests/good.json"),
          })

          local body = assert.res_status(401, r)
          local json = cjson.decode(body)
          assert.equals(json.error, "Authorization header is correct, but the token seems invalid")
        end)
        it("unauthorized request completions", function()
          local r = client:get("/huggingface/llm/v1/completions/unauthorized", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-completions/requests/good.json"),
          })

          local body = assert.res_status(401, r)
          local json = cjson.decode(body)
          assert.equals(json.error, "Authorization header is correct, but the token seems invalid")
        end)
      end)
      describe("huggingface bad request", function()
        it("bad chat request", function()
          local r = client:get("/huggingface/llm/v1/chat/good", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = { messages = ngx.null },
          })

          local body = assert.res_status(400, r)
          local json = cjson.decode(body)
          assert.equals(json.error.message, "request format not recognised")
        end)
        it("bad completions request", function()
          local r = client:get("/huggingface/llm/v1/completions/good", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = { prompt = ngx.null },
          })

          local body = assert.res_status(400, r)
          local json = cjson.decode(body)
          assert.equals(json.error.message, "request format not recognised")
        end)
      end)
      describe("huggingface bad response", function()
        it("bad chat response", function()
          local r = client:get("/huggingface/llm/v1/chat/bad-response/model-loading", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/requests/good.json"),
          })

          local body = assert.res_status(503, r)
          local json = cjson.decode(body)
          assert.equals(json.error, "Model mistralai/Mistral-7B-Instruct-v0.2 is currently loading")
        end)
        it("bad completions request", function()
          local r = client:get("/huggingface/llm/v1/chat/bad-response/model-timeout", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = pl_file.read("spec/fixtures/ai-proxy/huggingface/llm-v1-chat/requests/good.json"),
          })
          local body = assert.res_status(504, r)
          local json = cjson.decode(body)
          assert.equals(json.error, "Model mistralai/Mistral-7B-Instruct-v0.2 time out")
        end)
      end)
    end)
  end
end
