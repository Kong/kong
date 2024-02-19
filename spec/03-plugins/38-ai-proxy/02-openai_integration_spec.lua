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
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/good.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/chat/bad_upstream_response" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                local token = ngx.req.get_headers()["authorization"]
                if token == "Bearer openai-key" then
                  ngx.req.read_body()
                  local body, err = ngx.req.get_body_data()
                  body, err = json.decode(body)
                  
                  if err or (body.messages == ngx.null) then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_upstream_response.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/chat/bad_request" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                
                ngx.status = 400
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
              }
            }

            location = "/llm/v1/chat/internal_server_error" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                
                ngx.status = 500
                ngx.header["content-type"] = "text/html"
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/internal_server_error.html"))
              }
            }


            location = "/llm/v1/completions/good" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                local json = require("cjson.safe")

                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                local token = ngx.req.get_headers()["authorization"]
                local token_query = ngx.req.get_uri_args()["apikey"]

                if token == "Bearer openai-key" or token_query == "openai-key" or body.apikey == "openai-key" then
                  
                  if err or (body.messages == ngx.null) then
                    ngx.status = 400
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/bad_request.json"))
                  else
                    ngx.status = 200
                    ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/good.json"))
                  end
                else
                  ngx.status = 401
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/unauthorized.json"))
                end
              }
            }

            location = "/llm/v1/completions/bad_request" {
              content_by_lua_block {
                local pl_file = require "pl.file"
                
                ngx.status = 400
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/responses/bad_request.json"))
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
        paths = { "/openai/llm/v1/chat/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = chat_good.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 200 chat good with statistics disabled
      local chat_good_no_stats = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/good-without-stats" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_no_stats.id },
        config = {
          route_type = "llm/v1/chat",
          logging = {
            log_payloads = false,
            log_statistics = false,
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = chat_good_no_stats.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 200 chat good with all logging enabled
      local chat_good_log_payloads = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/good-with-payloads" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_log_payloads.id },
        config = {
          route_type = "llm/v1/chat",
          logging = {
            log_payloads = true,
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        },
      }
      bp.plugins:insert {
        name = "file-log",
        route = { id = chat_good_log_payloads.id },
        config = {
          path = "/dev/stdout",
        },
      }
      --

      -- 200 chat bad upstream response with one option
      local chat_bad_upstream = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat/bad_upstream_response" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_bad_upstream.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_upstream_response"
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
        paths = { "/openai/llm/v1/completions/good" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo-instruct",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/good"
            },
          },
        },
      }
      --

      -- 200 completions good using query param key
      local completions_good_one_query_param = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/completions/query-param-auth" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good_one_query_param.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            param_name = "apikey",
            param_value = "openai-key",
            param_location = "query",
          },
          model = {
            name = "gpt-3.5-turbo-instruct",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/good"
            },
          },
        },
      }
      --

      -- 200 completions good using post body key
      local completions_good_post_body_key = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/completions/post-body-auth" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = completions_good_post_body_key.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            param_name = "apikey",
            param_value = "openai-key",
            param_location = "body",
          },
          model = {
            name = "gpt-3.5-turbo-instruct",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/good"
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
        paths = { "/openai/llm/v1/chat/unauthorized" }
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
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
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
        paths = { "/openai/llm/v1/chat/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/bad_request"
            },
          },
        },
      }
      --

      -- 400 bad request completions
      local chat_400_comp = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/completions/bad_request" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_400_comp.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo-instruct",
            provider = "openai",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/completions/bad_request"
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
        paths = { "/openai/llm/v1/chat/internal_server_error" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_500.id },
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
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/internal_server_error"
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
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    describe("openai general", function()
      it("logs statistics", function()
        local r = client:get("/openai/llm/v1/chat/good", {
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
        assert.equals(json.model, "gpt-3.5-turbo-0613")
        assert.equals(json.object, "chat.completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)

        -- TODO TEST THE LOG FILE
      end)

      it("does not log statistics", function()
        local r = client:get("/openai/llm/v1/chat/good-without-stats", {
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
        assert.equals(json.model, "gpt-3.5-turbo-0613")
        assert.equals(json.object, "chat.completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
        
        -- TODO TEST THE LOG FILE
      end)

      it("logs payloads", function()
        local r = client:get("/openai/llm/v1/chat/good-with-payloads", {
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
        assert.equals(json.model, "gpt-3.5-turbo-0613")
        assert.equals(json.object, "chat.completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)

        -- TODO TEST THE LOG FILE
      end)

      it("internal_server_error request", function()
        local r = client:get("/openai/llm/v1/chat/internal_server_error", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        
        local body = assert.res_status(500 , r)
        assert.is_not_nil(body)
      end)

      it("unauthorized request", function()
        local r = client:get("/openai/llm/v1/chat/unauthorized", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        
        local body = assert.res_status(401 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.code, "invalid_api_key")
      end)

      it("tries to override model", function()
        local r = client:get("/openai/llm/v1/chat/good", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good_own_model.json"),
        })
        
        local body = assert.res_status(400, r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.message, "cannot use own model for this instance")
      end)
    end)

    describe("openai llm/v1/chat", function()
      it("good request", function()
        local r = client:get("/openai/llm/v1/chat/good", {
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
        assert.equals(json.model, "gpt-3.5-turbo-0613")
        assert.equals(json.object, "chat.completion")

        assert.is_table(json.choices)
        assert.is_table(json.choices[1].message)
        assert.same({
          content = "The sum of 1 + 1 is 2.",
          role = "assistant",
        }, json.choices[1].message)
      end)

      it("bad upstream response", function()
        local r = client:get("/openai/llm/v1/chat/bad_upstream_response", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/good.json"),
        })
        
        -- check we got internal server error
        local body = assert.res_status(500 , r)
        local json = cjson.decode(body)
        assert.is_truthy(json.error)
        assert.equals(json.error.message, "transformation failed from type openai://llm/v1/chat: 'choices' not in llm/v1/chat response")
      end)

      it("bad request", function()
        local r = client:get("/openai/llm/v1/chat/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/requests/bad_request.json"),
        })
        
        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals(json.error.message, "request format not recognised")
      end)
    end)

    describe("openai llm/v1/completions", function()
      it("good request", function()
        local r = client:get("/openai/llm/v1/completions/good", {
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
        assert.equals("gpt-3.5-turbo-instruct", json.model)
        assert.equals("text_completion", json.object)

        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same("\n\nI am a language model AI created by OpenAI. I can answer questions", json.choices[1].text)
      end)

      it("bad request", function()
        local r = client:get("/openai/llm/v1/completions/bad_request", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-completions/requests/bad_request.json"),
        })
        
        local body = assert.res_status(400 , r)
        local json = cjson.decode(body)

        -- check this is in the 'kong' response format
        assert.is_truthy(json.error)
        assert.equals("request format not recognised", json.error.message)
      end)
    end)

    describe("openai different auth methods", function()
      it("works with query param auth", function()
        local r = client:get("/openai/llm/v1/completions/query-param-auth", {
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
        assert.equals("gpt-3.5-turbo-instruct", json.model)
        assert.equals("text_completion", json.object)
        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same("\n\nI am a language model AI created by OpenAI. I can answer questions", json.choices[1].text)
      end)

      it("works with post body auth", function()
        local r = client:get("/openai/llm/v1/completions/post-body-auth", {
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
        assert.equals("gpt-3.5-turbo-instruct", json.model)
        assert.equals("text_completion", json.object)
        assert.is_table(json.choices)
        assert.is_table(json.choices[1])
        assert.same("\n\nI am a language model AI created by OpenAI. I can answer questions", json.choices[1].text)
      end)
    end)

    describe("one-shot request", function()
      it("success", function()
        local ai_driver = require("kong.llm.drivers.openai")
  
        local plugin_conf = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 1024,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/good"
            },
          },
        }
  
        local request = {
          messages = {
            [1] = {
              role = "system",
              content = "Some system prompt",
            },
            [2] = {
              role = "user",
              content = "Some question",
            }
          }
        }
  
        -- convert it to the specified driver format
        local ai_request = ai_driver.to_format(request, plugin_conf.model, "llm/v1/chat")
  
        -- send it to the ai service
        local ai_response, status_code, err = ai_driver.subrequest(ai_request, plugin_conf, {}, false)
        assert.is_nil(err)
        assert.equal(200, status_code)
  
        -- parse and convert the response
        local ai_response, _, err = ai_driver.from_format(ai_response, plugin_conf.model, plugin_conf.route_type)
        assert.is_nil(err)

        -- check it
        local response_table, err = cjson.decode(ai_response)
        assert.is_nil(err)
        assert.same(response_table.choices[1].message,
          {
            content = "The sum of 1 + 1 is 2.",
            role = "assistant",
          })
      end)

      it("404", function()
        local ai_driver = require("kong.llm.drivers.openai")
  
        local plugin_conf = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer openai-key",
          },
          model = {
            name = "gpt-3.5-turbo",
            provider = "openai",
            options = {
              max_tokens = 1024,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/llm/v1/chat/nowhere"
            },
          },
        }
  
        local request = {
          messages = {
            [1] = {
              role = "system",
              content = "Some system prompt",
            },
            [2] = {
              role = "user",
              content = "Some question",
            }
          }
        }
  
        -- convert it to the specified driver format
        local ai_request = ai_driver.to_format(request, plugin_conf.model, "llm/v1/chat")

        -- send it to the ai service
        local ai_response, status_code, err = ai_driver.subrequest(ai_request, plugin_conf, {}, false)
        assert.is_not_nil(err)
        assert.is_not_nil(ai_response)
        assert.equal(404, status_code)
      end)
    end)
  end)

end end
