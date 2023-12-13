local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_file = require "pl.file"

local PLUGIN_NAME = "ai-proxy"
local MOCK_PORT = 62349

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- set up mistral mock fixtures
      local fixtures = {
        http_mock = {},
      }
      
      fixtures.http_mock.llama2 = [[
        server {
          server_name llama2;
          listen ]]..MOCK_PORT..[[;
          
          default_type 'application/json';

          location = "/raw/llm/v1/chat" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer llama2-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if (err) or (not body) or (not body.inputs) or (body.inputs == ngx.null) or (not string.find((body and body.inputs) or "", "INST")) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/unauthorized.json"))
              end
            }
          }

          location = "/raw/llm/v1/completions" {
            content_by_lua_block {
              local pl_file = require "pl.file"
              local json = require("cjson.safe")

              local token = ngx.req.get_headers()["authorization"]
              if token == "Bearer llama2-key" then
                ngx.req.read_body()
                local body, err = ngx.req.get_body_data()
                body, err = json.decode(body)

                if (err) or (not body) or (not body.inputs) or (body.inputs == ngx.null) or (not string.find((body and body.inputs) or "", "INST")) then
                  ngx.status = 400
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/bad_request.json"))
                else
                  ngx.status = 200
                  ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/good.json"))
                end
              else
                ngx.status = 401
                ngx.print(pl_file.read("spec/fixtures/ai-proxy/llama2/raw/responses/unauthorized.json"))
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
        paths = { "/raw/llm/v1/chat/completions" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer llama2-key",
          },
          model = {
            name = "llama-2-7b-chat-hf",
            provider = "llama2",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              llama2_format = "raw",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/raw/llm/v1/chat",
            },
          },
        },
      }
      --

      -- 200 completions good with one option
      local chat_good = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/raw/llm/v1/completions" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer llama2-key",
          },
          model = {
            name = "llama-2-7b-chat-hf",
            provider = "llama2",
            options = {
              max_tokens = 256,
              temperature = 1.0,
              llama2_format = "raw",
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/raw/llm/v1/completions",
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

    describe("llama2 general", function()
      it("runs good request in chat format", function()
        local r = client:get("/raw/llm/v1/chat/completions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-chat.json"),
        })
        
        local body = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.equals(json.choices[1].message.content, "\n\nMissingno. is a glitch from a well-known video game.")
      end)

      it("runs good request in completions format", function()
        local r = client:get("/raw/llm/v1/completions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-completions.json"),
        })
        
        local body = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.equals(json.choices[1].text, "\n\nMissingno. is a glitch from a well-known video game.")
      end)
    end)
  end)

end end
