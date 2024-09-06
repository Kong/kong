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
            allow_override = true,
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

      local chat_good_no_allow_override = assert(bp.routes:insert {
        service = empty_service,
        protocols = { "http" },
        strip_path = true,
        paths = { "/raw/llm/v1/completions-no-allow-override" }
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = chat_good_no_allow_override.id },
        config = {
          route_type = "llm/v1/completions",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer llama2-key",
            allow_override = false,
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
      helpers.stop_kong()
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

        assert.equals(json.choices[1].message.content, "Is a well known font.")
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

        assert.equals(json.choices[1].text, "Is a well known font.")
      end)

      it("runs good request in completions format with client right auth", function()
        local r = client:get("/raw/llm/v1/completions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer llama2-key"
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-completions.json"),
        })

        local body = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.equals(json.choices[1].text, "Is a well known font.")
      end)

      it("runs good request in completions format with client wrong auth", function()
        local r = client:get("/raw/llm/v1/completions", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong"
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-completions.json"),
        })

        local body = assert.res_status(401, r)
        local json = cjson.decode(body)

        assert.equals(json.error, "Model requires a Pro subscription.")
      end)

      it("runs good request in completions format with client right auth and no allow_override", function()
        local r = client:get("/raw/llm/v1/completions-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer llama2-key"
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-completions.json"),
        })

        local body = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.equals(json.choices[1].text, "Is a well known font.")
      end)

      it("runs good request in completions format with client wrong auth and no allow_override", function()
        local r = client:get("/raw/llm/v1/completions-no-allow-override", {
          headers = {
            ["content-type"] = "application/json",
            ["accept"] = "application/json",
            ["Authorization"] = "Bearer wrong"
          },
          body = pl_file.read("spec/fixtures/ai-proxy/llama2/raw/requests/good-completions.json"),
        })

        local body = assert.res_status(200, r)
        local json = cjson.decode(body)

        assert.equals(json.choices[1].text, "Is a well known font.")
      end)

    end)

    describe("one-shot request", function()
      it("success", function()
        local ai_driver = require("kong.llm.drivers.llama2")

        local plugin_conf = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer llama2-key",
          },
          model = {
            name = "llama-2-7b-chat-hf",
            provider = "llama2",
            options = {
              max_tokens = 1024,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/raw/llm/v1/chat",
              llama2_format = "raw",
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
        local ai_request, content_type, err = ai_driver.to_format(request, plugin_conf.model, "llm/v1/chat")
        assert.is_nil(err)
        assert.is_not_nil(content_type)

        -- send it to the ai service
        local ai_response, status_code, err = ai_driver.subrequest(ai_request, plugin_conf, {}, false)
        assert.equal(200, status_code)
        assert.is_nil(err)

        -- parse and convert the response
        local ai_response, _, err = ai_driver.from_format(ai_response, plugin_conf.model, plugin_conf.route_type)
        assert.is_nil(err)

        -- check it
        local response_table, err = cjson.decode(ai_response)
        assert.is_nil(err)
        assert.same(response_table.choices[1].message,
          {
            content = "Is a well known font.",
            role = "assistant",
          })
      end)

      it("404", function()
        local ai_driver = require("kong.llm.drivers.llama2")

        local plugin_conf = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer llama2-key",
          },
          model = {
            name = "llama-2-7b-chat-hf",
            provider = "llama2",
            options = {
              max_tokens = 1024,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/raw/llm/v1/nowhere",
              llama2_format = "raw",
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

      it("401", function()
        local ai_driver = require("kong.llm.drivers.llama2")

        local plugin_conf = {
          route_type = "llm/v1/chat",
          auth = {
            header_name = "Authorization",
            header_value = "Bearer wrong-key",
          },
          model = {
            name = "llama-2-7b-chat-hf",
            provider = "llama2",
            options = {
              max_tokens = 1024,
              upstream_url = "http://"..helpers.mock_upstream_host..":"..MOCK_PORT.."/raw/llm/v1/chat",
              llama2_format = "raw",
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
        assert.equal(401, status_code)
      end)

    end)
  end)

end end
