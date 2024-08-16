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

      -- set up cohere mock fixtures
      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.cohere = [[
        server {
            server_name cohere;
            listen ]]..MOCK_PORT..[[;

            default_type 'application/json';


            location = "/llm/v1/chat/good" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                local token = ngx.req.get_headers()["authorization"]
                if token == "Bearer cohere-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)

                  if err or (not body.message)  then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/good.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/chat/bad_upstream_response" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                local token = ngx.req.get_headers()["authorization"]
                if token == "Bearer cohere-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)

                  if err or (not body.message) then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/bad_upstream_response.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/chat/bad_request" {
              content_by_lua_block {
                local pl_file = require "pl.file"

                ngx.status = 400
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/bad_request.json"))
              }
            }

            location = "/llm/v1/chat/internal_server_error" {
              content_by_lua_block {
                local pl_file = require "pl.file"

                ngx.status = 500
                ngx.header["content-type"] = "text/html"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/responses/internal_server_error.html"))
              }
            }


            location = "/llm/v1/completions/good" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                local token = ngx.req.get_headers()["authorization"]
                if token == "Bearer cohere-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)

                  if err or (not body.prompt) then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/responses/good.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/completions/bad_request" {
              content_by_lua_block {
                local pl_file = require "pl.file"

                ngx.status = 400
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/responses/bad_request.json"))
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

      -- 200 chat good with one option
      local chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/cohere/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer cohere-key",
            allow_override = true,
          },
          model = {
            name = "command",
            provider = "cohere",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
            },
          },
        },
      }
      local chat_good_no_allow_override = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/cohere/llm/v1/chat/good-no-allow-override" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_no_allow_override.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer cohere-key",
            allow_override = false,
          },
          model = {
            name = "command",
            provider = "cohere",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
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
        paths = { "/cohere/llm/v1/chat/bad_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_upstream_response",
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
        paths = { "/cohere/llm/v1/completions/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good.id },
        config = {
          route_type = "llm/v1/completions",
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/good",
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
        paths = { "/cohere/llm/v1/chat/unauthorized" }
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
            name = "command",
            provider = "cohere",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good",
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
        paths = { "/cohere/llm/v1/chat/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_request",
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
        paths = { "/cohere/llm/v1/completions/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
        config = {
          route_type = "llm/v1/completions",
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/bad_request",
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
        paths = { "/cohere/llm/v1/chat/internal_server_error" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_500.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/internal_server_error",
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

    describe("cohere general", function()
      it("internal_server_error request", function()
        local r = client:get("/cohere/llm/v1/chat/internal_server_error", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(500 , r)
        assert.is_not_nil(body)
      end)

      it("unauthorized request", function()
        local r = client:get("/cohere/llm/v1/chat/unauthorized", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.message, "invalid api token")
      end)
    end)

    describe("cohere llm/v1/chat", function()
      it("good request", function()
        local r = client:get("/cohere/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "command")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "cohere/command")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with right client auth", function()
        local r = client:get("/cohere/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer cohere-key",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "command")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "cohere/command")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with wrong client auth", function()
        local r = client:get("/cohere/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.message)
        assert.equals(json.message, "invalid api token")
      end)

      it("good request with right client auth and no allow_override", function()
        local r = client:get("/cohere/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer cohere-key",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "command")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "cohere/command")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("good request with wrong client auth and no allow_override", function()
        local r = client:get("/cohere/llm/v1/chat/good-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "command")
        assert.equals(json.object, "chat.completion")
        assert.equals(r.headers["X-Kong-LLM-Model"], "cohere/command")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("bad upstream response", function()
        local r = client:get("/cohere/llm/v1/chat/bad_upstream_response", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/good.json"),
        })

        -- check we got internal server error
        local body = assert.res_status(500 , r)
        local json = cjson.decode(body) 
        assert.equals(json.error.message, "transformation failed from type cohere://llm/v1/chat: 'text' or 'generations' missing from cohere response body")
      end)

      it("bad request", function()
        local r = client:get("/cohere/llm/v1/chat/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-chat/requests/bad_request.json"),
        })

        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.error.message, "request format not recognised")
      end)
    end)

    describe("cohere llm/v1/completions", function()
      it("good request", function()
        local r = client:get("/cohere/llm/v1/completions/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/requests/good.json"),
        })

        local body = assert.res_status(200 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.equals(json.model, "command")
        assert.equals(json.object, "text_completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same("1 + 1 is 2.", json.choices[1].text)
      end)

      it("bad request", function()
        local r = client:get("/cohere/llm/v1/completions/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/cohere/llm-v1-completions/requests/bad_request.json"),
        })

        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals("request format not recognised", json.error.message)
      end)
    end)
  end)

end end
