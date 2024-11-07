local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up mistral mock fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.mistral = [[
        server {
          server_name mistral;
          listen ]]..MOCK_PORT..[[;

          default_type 'application/json';

          location = "/v1/chat/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer mistral-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.messages == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/mistral/llm-v1-chat/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
              end
            }
          }

          location = "/v1/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer mistral-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if err or (body.prompt == ngx.null) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/mistral/llm-v1-completions/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/unauthorized.json"))
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

      -- 200 chat good with one option
      local chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
            allow_override = true,
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
        },
      }

      local chat_good_no_allow_override = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/good-no-allow-override" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_no_allow_override.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
            allow_override = false,
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
        },
      }
      --

      -- 200 chat bad upstream response with one option
      local chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/bad_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
        },
      }
      --

      -- 200 completions good with one option
      local completions_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/completions/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/completions",
            },
          },
        },
      }
      --

      -- 401 unauthorized
      local chat_401 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/unauthorized" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_401.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer wrong-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
        },
      }
      --

      -- 400 bad request chat
      local chat_400 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
        },
      }
      --

      -- 400 bad request completions
      local chat_400 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/completions/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/completions",
            },
          },
        },
      }
      --

      -- 500 internal server error
      local chat_500 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/mistral/llm/v1/chat/internal_server_error" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_500.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer mistral-key",
          },
          model = {
            name = "mistralai/Mistral-7B-Instruct-v0.1-instruct",
            provider = "mistral",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              mistral_format = "openai",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/v1/chat/completions",
            },
          },
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

    describe("mistral llm/v1/chat", function()
      it("good request", function()
        local r = client:get("/mistral/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200
        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "mistralai/Mistral-7B-Instruct-v0.1-instruct")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "mistral/mistralai/Mistral-7B-Instruct-v0.1-instruct")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client right auth", function()
        local r = client:get("/mistral/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer mistral-key",

          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200
        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "mistralai/Mistral-7B-Instruct-v0.1-instruct")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "mistral/mistralai/Mistral-7B-Instruct-v0.1-instruct")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client wrong auth", function()
        local r = client:get("/mistral/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200

        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.code, "invalid_api_key")
      end)

      it("good request with client right auth and no allow_override", function()
        local r = client:get("/mistral/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer mistral-key",

          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200
        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "mistralai/Mistral-7B-Instruct-v0.1-instruct")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "mistral/mistralai/Mistral-7B-Instruct-v0.1-instruct")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client wrong auth and no allow_override", function()
        local r = client:get("/mistral/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200
        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "mistralai/Mistral-7B-Instruct-v0.1-instruct")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "mistral/mistralai/Mistral-7B-Instruct-v0.1-instruct")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)
    end)

    describe("mistral llm/v1/completions", function()
      it("good request", function()
        local r = client:get("/mistral/llm/v1/completions/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/requests/good.json"),
        })

        -- validate that the request succeeded, response status 200
        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals("cmpl-8TBeaJVQIhE9kHEJbk1RnKzgFxIqN", json.id)
        assert.equals("mistralai/Mistral-7B-Instruct-v0.1-instruct", json.model)
        assert.equals("text_completion", json.object)

        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same("\n\nI am a language model AI created by OpenAI. I can answer questions", json.choices[1].text)
      end)
    end)
  end)

end end
