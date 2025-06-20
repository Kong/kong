local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"
local deepcompare  = require("pl.tablex").deepcompare

local ANTHROPIC_MOCK = pl_file.read("spec/fixtures/ai-proxy/mock_servers/anthropic.lua.txt")
local PLUGIN_NAME = "ai-proxy"

for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client
    local MOCK_PORT

    lazy_setup(function()
      MOCK_PORT = helpers.get_available_port()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up anthropic mock fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.anthropic = string.format(ANTHROPIC_MOCK, MOCK_PORT)

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
        paths = { "/anthropic/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
            allow_override = true,
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
              anthropic_version = "2023-06-01",
            },
          },
        },
      }

      local chat_good_no_allow_override = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/good-no-allow-override" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_no_allow_override.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
            allow_override = false,
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
              anthropic_version = "2023-06-01",
            },
          },
        },
      }
      --

      -- 200 chat bad upstream response with one option
      local chat_bad = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/bad_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_bad.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_upstream_response",
              anthropic_version = "2023-06-01",
            },
          },
        },
      }
      --

      -- 200 chat no-usage response
      local chat_no_usage = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/no_usage_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_no_usage.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/no_usage_upstream_response",
              anthropic_version = "2023-06-01",
            },
          },
        },
      }
      --

      -- 200 chat malformed-usage response
      local chat_malformed_usage = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/malformed_usage_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_malformed_usage.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/malformed_usage_upstream_response",
              anthropic_version = "2023-06-01",
            },
          },
        },
      }

      -- 200 completions good with one option
      local completions_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/completions/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/good",
              anthropic_version = "2023-06-01",
            },
          },
          logging = {
            log_statistics = false,  -- anthropic does not support statistics
          },
        },
      }
      --

      -- 200 chat tool_choice response
      local chat_tool_choice = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/tool_choice" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_tool_choice.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/tool_choice",
              anthropic_version = "2023-06-01",
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
        paths = { "/anthropic/llm/v1/chat/unauthorized" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_401.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "wrong-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
              anthropic_version = "2023-06-01",
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
        paths = { "/anthropic/llm/v1/chat/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_request",
              anthropic_version = "2023-06-01",
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
        paths = { "/anthropic/llm/v1/completions/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/bad_request",
              anthropic_version = "2023-06-01",
            },
          },
          logging = {
            log_statistics = false,  -- anthropic does not support statistics
          },
        },
      }
      --

      -- 500 internal server error
      local chat_500 = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/anthropic/llm/v1/chat/internal_server_error" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_500.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "x-api-key",
            header_value = "anthropic-key",
          },
          model = {
            name = "claude-2.1",
            provider = "anthropic",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/internal_server_error",
              anthropic_version = "2023-06-01",
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

    describe("anthropic general", function()
      it("internal_server_error request", function()
        local r = client:get("/anthropic/llm/v1/chat/internal_server_error", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(500 , r)
        assert.is_not_nil(body)
      end)

      it("unauthorized request", function()
        local r = client:get("/anthropic/llm/v1/chat/unauthorized", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.type, "authentication_error")
      end)
    end)

    describe("anthropic llm/v1/chat", function()
      it("good request", function()
        local r = client:get("/anthropic/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        -- assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "claude-2.1")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "anthropic/claude-2.1")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client right header auth", function()
        local r = client:get("/anthropic/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["x-api-key"] = "anthropic-key",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        -- assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "claude-2.1")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "anthropic/claude-2.1")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client wrong header auth", function()
        local r = client:get("/anthropic/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["x-api-key"] = "wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.type, "authentication_error")
      end)

      it("good request with client right header auth and no allow_override", function()
        local r = client:get("/anthropic/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["x-api-key"] = "anthropic-key",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        -- assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "claude-2.1")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "anthropic/claude-2.1")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with client wrong header auth and no allow_override", function()
        local r = client:get("/anthropic/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["x-api-key"] = "wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        -- assert.equals(json.id, "chatcmpl-8T6YwgvjQVVnGbJ2w8hpOA17SeNy2")
        assert.equals(json.model, "claude-2.1")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "anthropic/claude-2.1")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("bad upstream response", function()
        local r = client:get("/anthropic/llm/v1/chat/bad_upstream_response", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        -- check we got internal server error
        local body = assert.res_status(500 , r)
        local json = cjson.decode(body) 
        assert.equals(json.error.message, "transformation failed from type anthropic://llm/v1/chat: 'content' not in anthropic://llm/v1/chat response")
      end)

      it("bad request", function()
        local r = client:get("/anthropic/llm/v1/chat/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/bad_request.json"),
        })

        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.error.message, "request body doesn't contain valid prompts")
      end)

      it("no usage response", function()
        local r = client:get("/anthropic/llm/v1/chat/no_usage_upstream_response", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)
        assert.equals(json.usage, "no usage data returned from upstream")
      end)

      it("malformed usage response", function()
        local r = client:get("/anthropic/llm/v1/chat/malformed_usage_upstream_response", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)
        assert.is_truthy(deepcompare(json.usage, {}))
      end)

      it("tool_choice conversion", function()
        local function get_converted_tool_choice(input)
          local body = pl_file.read(input)
          -- rewrite the model so we can reuse the same test fixture with different models
          body = cjson.decode(body)
          body.model = "claude-2.1" -- anthropic model name
          local r = client:post("/anthropic/llm/v1/chat/tool_choice", {
            headers = {
              ["content-type"] = "application/json",
              ["accept"] = "application/json",
            },
            body = cjson.encode(body),
          })
          r:read_body()
          local sent = r.headers["tool-choice"]
          if not sent then
            return nil
          end
          return cjson.decode(sent)
        end

        for _, case in ipairs({
          {input = "spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/tool_choice_auto.json",
           output = {type = "auto"}},
          {input = "spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/tool_choice_none.json",
           output = {type = "none"}},
          {input = "spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/tool_choice_required.json",
           output = {type = "any"}},
          {input = "spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/tool_choice_object_function.json",
           output = {type = "tool", name = "my_function"}},
        }) do
          local r = get_converted_tool_choice(case.input)
          assert.same(case.output, r)
        end
      end)
    end)

    describe("anthropic llm/v1/completions", function()
      it("good request", function()
        local r = client:get("/anthropic/llm/v1/completions/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-completions/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "claude-2.1")
        assert.equals(json.object, "text_completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same(" Hello! My name is Claude.", json.choices[1].text)
      end)

      it("bad request", function()
        local r = client:get("/anthropic/llm/v1/completions/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/anthropic/llm-v1-completions/requests/bad_request.json"),
        })

        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.error.message, "request body doesn't contain valid prompts")
      end)
    end)
  end)

end
