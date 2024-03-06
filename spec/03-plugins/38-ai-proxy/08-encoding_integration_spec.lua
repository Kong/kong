local helpers = require "spec.helpers"
local cjson = require "cjson"
local inflate_gzip = require("kong.tools.gzip").inflate_gzip

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = helpers.get_available_port()

local openai_driver = require("kong.llm.drivers.openai")

local format_stencils = {
  llm_v1_chat = {
    good = {

      user_request = {
        messages = {
          [1] = {
            role = "system",
            content = "You are a scientist.",
          },
          [2] = {
            role = "user",
            content = "Why can't you divide by zero?",
          },
        },
      },

      provider_response = {
        choices = {
          [1] = {
            finish_reason = "stop",
            index = 0,
            messages = {
              role = "assistant",
              content = "Dividing by zero is undefined in mathematics because it leads to results that are contradictory or nonsensical.",
            },
          },
        },
        created = 1702325640,
        id = "chatcmpl-8Ugx63a79wKACVkaBbKnR2C2HPcxT",
        model = "gpt-4-0613",
        object = "chat.completion",
        system_fingerprint = nil,
        usage = {
          completion_tokens = 139,
          prompt_tokens = 130,
          total_tokens = 269,
        },
      },

    },


    faulty = {

      provider_response = {
        your_request = {
          was_not = "correct but for some reason i return 200 anyway",
        },
      },

    },

    unauthorized = {

      provider_response = {
        error = {
          message = "bad API key",
        }
      },

    },

    error = {

      provider_response = {
        error = {
          message = "some failure",
        },
      },
    },

    error_faulty = {

      provider_response = {
        bad_message = {
          bad_error = {
            unauthorized = "some failure with weird json",
          },
        }
      },

    },

  },
}

local plugin_conf = {
  route_type = "llm/v1/chat",
  auth = {
    header_name = "Authorization",
    header_value = "Bearer openai-key",
  },
  model = {
    name = "gpt-4",
    provider = "openai",
    options = {
      max_tokens = 256,
      temperature = 1.0,
    },
  },
}

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
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

      -- openai llm driver will always send to this port, if var is set
      helpers.setenv("OPENAI_TEST_PORT", tostring(MOCK_PORT))

      fixtures.http_mock.openai = [[
        server {
            server_name openai;
            listen ]]..MOCK_PORT..[[;

            default_type 'application/json';

            location = "/v1/chat/completions" {
              content_by_lua_block {
                local json = require("cjson.safe")
                local inflate_gzip  = require("kong.tools.gzip").inflate_gzip
                local deflate_gzip  = require("kong.tools.gzip").deflate_gzip

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
                    -- ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/bad_request.json"))
                  else
                    local test_type = ngx.req.get_headers()['x-test-type']

                    -- switch based on test type requested
                    if test_type == ngx.null or test_type == "200" then
                      ngx.status = 200
                      ngx.header["content-encoding"] = "gzip"
                      local response = deflate_gzip(']] .. cjson.encode(format_stencils.llm_v1_chat.good.provider_response) .. [[')
                      ngx.print(response)
                    elseif test_type == "200_FAULTY" then
                      ngx.status = 200
                      ngx.header["content-encoding"] = "gzip"
                      local response = deflate_gzip(']] .. cjson.encode(format_stencils.llm_v1_chat.faulty.provider_response) .. [[')
                      ngx.print(response)
                    elseif test_type == "401" then
                      ngx.status = 401
                      ngx.header["content-encoding"] = "gzip"
                      local response = deflate_gzip(']] .. cjson.encode(format_stencils.llm_v1_chat.unauthorized.provider_response) .. [[')
                      ngx.print(response)
                    elseif test_type == "500" then
                      ngx.status = 500
                      ngx.header["content-encoding"] = "gzip"
                      local response = deflate_gzip(']] .. cjson.encode(format_stencils.llm_v1_chat.error.provider_response) .. [[')
                      ngx.print(response)
                    elseif test_type == "500_FAULTY" then
                      ngx.status = 500
                      ngx.header["content-encoding"] = "gzip"
                      local response = deflate_gzip(']] .. cjson.encode(format_stencils.llm_v1_chat.error_faulty.provider_response) .. [[')
                      ngx.print(response)
                    end
                  end
                else
                  ngx.status = 401
                  -- ngx.print(pl_file.read("spec/fixtures/ai-proxy/openai/llm-v1-chat/responses/unauthorized.json"))
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

      -- 200 chat good, gzipped from server
      local openai_chat = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/openai/llm/v1/chat" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = openai_chat.id },
        config = plugin_conf,
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


    ---- TESTS
    describe("returns deflated response to client", function()
      it("200 from LLM", function()
        local r = client:get("/openai/llm/v1/chat", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["x-test-type"] = "200",
          },
          body = format_stencils.llm_v1_chat.good.user_request,
        })

        -- validate that the request succeeded, response status 200
        local actual_response_string = assert.res_status(200 , r)
        actual_response_string = inflate_gzip(actual_response_string)
        local actual_response, err = cjson.decode(actual_response_string)
        assert.is_falsy(err)

        -- execute the response format transformer manually
        local expected_response_string, err = cjson.encode(format_stencils.llm_v1_chat.good.provider_response)
        assert.is_falsy(err)

        local expected_response, err = openai_driver.from_format(expected_response_string, plugin_conf.model, plugin_conf.route_type)
        assert.is_falsy(err)
        expected_response, err = cjson.decode(expected_response)
        assert.is_falsy(err)

        -- compare the webserver vs code responses objects
        assert.same(expected_response, actual_response)
      end)
    end)

    it("200 from LLM but with faulty response format", function()
      local r = client:get("/openai/llm/v1/chat", {
        headers = {
          ["content-type"] = "application/json",
          ["accept"] = "application/json",
          ["x-test-type"] = "200_FAULTY",
        },
        body = format_stencils.llm_v1_chat.good.user_request,
      })

      -- validate that the request succeeded, response status 200
      local actual_response_string = assert.res_status(500 , r)
      actual_response_string = inflate_gzip(actual_response_string)
      local actual_response, err = cjson.decode(actual_response_string)
      assert.is_falsy(err)

      -- compare the webserver vs expected error
      assert.same({ error = { message = "transformation failed from type openai://llm/v1/chat: 'choices' not in llm/v1/chat response" }}, actual_response)
    end)

    it("401 from LLM", function()
      local r = client:get("/openai/llm/v1/chat", {
        headers = {
          ["content-type"] = "application/json",
          ["accept"] = "application/json",
          ["x-test-type"] = "401",
        },
        body = format_stencils.llm_v1_chat.good.user_request,
      })

      -- validate that the request succeeded, response status 200
      local actual_response_string = assert.res_status(401 , r)
      actual_response_string = inflate_gzip(actual_response_string)
      local actual_response, err = cjson.decode(actual_response_string)
      assert.is_falsy(err)

      -- compare the webserver vs expected error
      assert.same({ error = { message = "bad API key" }}, actual_response)
    end)

    it("500 from LLM", function()
      local r = client:get("/openai/llm/v1/chat", {
        headers = {
          ["content-type"] = "application/json",
          ["accept"] = "application/json",
          ["x-test-type"] = "500",
        },
        body = format_stencils.llm_v1_chat.good.user_request,
      })

      -- validate that the request succeeded, response status 200
      local actual_response_string = assert.res_status(500 , r)
      actual_response_string = inflate_gzip(actual_response_string)
      local actual_response, err = cjson.decode(actual_response_string)
      assert.is_falsy(err)

      -- compare the webserver vs expected error
      assert.same({ error = { message = "some failure" }}, actual_response)
    end)

    it("500 from LLM but with faulty response format", function()
      local r = client:get("/openai/llm/v1/chat", {
        headers = {
          ["content-type"] = "application/json",
          ["accept"] = "application/json",
          ["x-test-type"] = "500_FAULTY",
        },
        body = format_stencils.llm_v1_chat.good.user_request,
      })

      -- validate that the request succeeded, response status 200
      local actual_response_string = assert.res_status(500 , r)
      actual_response_string = inflate_gzip(actual_response_string)
      local actual_response, err = cjson.decode(actual_response_string)
      assert.is_falsy(err)

      -- compare the webserver vs expected error
      assert.same({ bad_message = { bad_error = { unauthorized = "some failure with weird json" }}}, actual_response)
    end)
  end)
  ----

end end
