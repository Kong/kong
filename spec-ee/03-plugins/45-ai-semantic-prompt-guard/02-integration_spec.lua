-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local PLUGIN_NAME = "ai-semantic-prompt-guard"
local REDIS_PORT = tonumber(os.getenv("KONG_SPEC_TEST_REDIS_STACK_PORT") or 6379)
local MOCK_PORT = helpers.get_available_port()


for _, strategy in helpers.all_strategies() do
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local fixtures = {
        http_mock = {},
      }

      fixtures.http_mock.mistral = [[
        server {
          server_name mistral;
          listen ]]..MOCK_PORT..[[;
          
          default_type 'application/json';

          location = "/v1/embeddings" {
            content_by_lua_block {
              local json = require("cjson.safe")
              ngx.req.read_body()
              local data, err = ngx.req.get_body_data()
              if err then
                ngx.status = 500
                ngx.say(json.encode({ message = "error reading body" }))
                return
              end

              local body = json.decode(data)
              local prompt = body.input

              local known_text_embeddings = {
                ["dog"] = { 0.56267416, -0.20551957, -0.047182854, 0.79933304 },
                ["cat"] = { 0.4653789, -0.42677408, -0.29335415, 0.717795 },
                ["capacitor"] = { 0.350534, -0.025470039, -0.9204002, -0.17129119 },
                ["smell"] = { 0.23342973, -0.08322083, -0.8492907, -0.46614397 },
                ["Non-Perturbative Quantum Field Theory and Resurgence in Supersymmetric Gauge Theories"] = {
                  -0.6826024, -0.08655233, -0.72073454, -0.084287055,
                  -0.6826024,
                  -0.08655233,
                  -0.72073454,
                  -0.084287055,
                },
                ["taco"] = { -0.4407651, -0.85174876, -0.27901474, -0.048999753 },
                ["If it discuss any topic about Amazon"] = { -0.86724466, 0.36718428, -0.21300745, -0.26017338 },
                ["If it discuss any topic about Microsoft"] = { -0.8649115, 0.2526763, -0.41767937, -0.11673351 },
                ["If it discuss any topic about Google"] = { -0.8108202, -0.22810346, -0.3790472, -0.38322666 },
                ["If it discuss any topic about Apple"] = { -0.8892975, 0.30626073, -0.336221, 0.048061296 },
                ["Tell me something about Microsoft"] = { -0.48062202, -0.4189232, -0.7663229, -0.07908846 },
                ["Tell me more things about Microsoft"] = { -0.48062202, -0.4189232, -0.7663229, -0.07908846 },
                ["Tell me something about Amazon"] = { -0.9346679, 0.10783355, -0.13593763, -0.31030443 },
                ["Tell me more things about Amazon"] = { -0.9346679, 0.10783355, -0.13593763, -0.31030443 },
                ["Tell me more things about Amazon Tell me something about Amazon "] = { -0.9346679, 0.10783355, -0.13593763, -0.31030443 },
                ["Tell me something about Google"] = { -0.3132111, -0.87082464, -0.33971936, -0.16779166 },
                ["Tell me more things about Google"] = { -0.3132111, -0.87082464, -0.33971936, -0.16779166 },
                ["Tell me more things about Google Tell me something about Google "] = { -0.3132111, -0.87082464, -0.33971936, -0.16779166 },
              }
              ngx.log(ngx.ERR, "prompt: ", prompt)
              local embeddings = known_text_embeddings[prompt]
              if not embeddings then
                ngx.status = 400
                ngx.say(json.encode({ message = "prompt not found" }))
                return
              end

              local gzip = require("kong.tools.gzip")
              ngx.header["Content-Encoding"] = "gzip"
              local embeddings_t = {
                data = {
                  {
                    embedding = embeddings,  
                  },
                } 
              }
              local body = gzip.deflate_gzip(json.encode(embeddings_t))
              ngx.say(body)
            }
          }
        }
      ]]

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- both
      local permit_history = bp.routes:insert({
        paths = { "~/permit-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = permit_history.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = false,
              deny_prompts = {
                [1] = "If it discuss any topic about Amazon",
                [2] = "If it discuss any topic about Microsoft",
              },
              allow_prompts = {
                [1] = "If it discuss any topic about Google",
                [2] = "If it discuss any topic about Apple",
              },
          },
        },
      }

      local block_history = bp.routes:insert({
        paths = { "~/block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = true,
              deny_prompts = {
                [1] = "If it discuss any topic about Amazon",
                [2] = "If it discuss any topic about Microsoft",
              },
              allow_prompts = {
                [1] = "If it discuss any topic about Google",
                [2] = "If it discuss any topic about Apple",
              },
          },
        },
      }
      --

      -- allows only
      local permit_history_allow_only = bp.routes:insert({
        paths = { "~/allow-only-permit-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = permit_history_allow_only.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = false,
              allow_prompts = {
                [1] = "If it discuss any topic about Google",
                [2] = "If it discuss any topic about Apple",
              },
          },
        },
      }

      local block_history_allow_only = bp.routes:insert({
        paths = { "~/allow-only-block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history_allow_only.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = true,
              allow_prompts = {
                [1] = "If it discuss any topic about Google",
                [2] = "If it discuss any topic about Apple",
              },
          },
        },
      }
      --

      -- denies only
      local permit_history_deny_only = bp.routes:insert({
        paths = { "~/deny-only-permit-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = permit_history_deny_only.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = false,
              deny_prompts = {
                [1] = "If it discuss any topic about Amazon",
              },
          },
        },
      }

      local block_history_deny_only = bp.routes:insert({
        paths = { "~/deny-only-block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history_deny_only.id },
        config = {
          embeddings = {
            model = {
              provider = "mistral",
              name = "text-embedding-3-large",
              options = {
                upstream_url = "http://127.0.0.1:" .. MOCK_PORT .. "/v1/embeddings",
              },
            },
          },
          vectordb = {
              strategy = "redis",
              distance_metric = "cosine",
              threshold = 0.5,
              dimensions = 4,
              redis = {
                  host = "localhost",
                  port = REDIS_PORT,
              },
          },
          rules = {
              match_all_conversation_history = false,
              deny_prompts = {
                [1] = "If it discuss any topic about Amazon",
                [2] = "If it discuss any topic about Microsoft",
              },
          },
        },
      }
      --

      --
      assert(helpers.start_kong({
        log_level = "info",
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
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



    -- both
    it("allows message with 'allow' and 'deny' set, with history", function()
      local r = client:get("/permit-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Google"
              },
              {
                "role": "assistant",
                "content": "Google is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Google"
              }
            ]
          }
        ]],
        method = "POST",
      })

      -- the body is just an echo, don't need to test it
      assert.response(r).has.status(200)
    end)

    it("deny message with 'allow' and 'deny' set, with history", function()
      local r = client:get("/permit-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Amazon"
              },
              {
                "role": "assistant",
                "content": "Amazon is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Amazon"
              }
            ]
          }
        ]],
        method = "POST",
      })
      assert.response(r).has.status(400)
    end)

    it("allows message with 'allow' and 'deny' set, without history", function()
      local r = client:get("/block-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Google"
              },
              {
                "role": "assistant",
                "content": "Google is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Google"
              }
            ]
          }
        ]],
        method = "POST",
      })

      -- the body is just an echo, don't need to test it
      assert.response(r).has.status(200)
    end)
  
    it("deny message with 'allow' and 'deny' set, without history", function()
      local r = client:get("/block-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Amazon"
              },
              {
                "role": "assistant",
                "content": "Amazon is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Amazon"
              }
            ]
          }
        ]],
        method = "POST",
      })

    -- the body is just an echo, don't need to test it
    assert.response(r).has.status(400)
    end)


    -- allows only
    it("allows message with 'allow' only set, with history", function()
      local r = client:get("/allow-only-permit-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Google"
              },
              {
                "role": "assistant",
                "content": "Google is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Google"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(200)
    end)


    it("allows message with 'allow' only set, without history", function()
      local r = client:get("/allow-only-block-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Google"
              },
              {
                "role": "assistant",
                "content": "Google is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Google"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(200)
    end)

    -- denies only
    it("allows message with 'deny' only set, permit history", function()
      local r = client:get("/deny-only-permit-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },

        -- this will be permitted, because the BAD PHRASE is only in chat history,
        -- which the developer "controls"
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Google"
              },
              {
                "role": "assistant",
                "content": "Google is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Google"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(200)
    end)


    it("blocks message with 'deny' only set, permit history", function()
      local r = client:get("/deny-only-permit-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },

        -- this will be blocks, because the BAD PHRASE is in the latest chat message,
        -- which the user "controls"
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Amazon"
              },
              {
                "role": "assistant",
                "content": "Amazon is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Amazon"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(400)
    end)

    it("blocks message with 'deny' only set, scan history", function()
      local r = client:get("/deny-only-block-history", {
        headers = {
          ["Content-Type"] = "application/json",
        },

        -- this will NOT be permitted, because the BAD PHRASE is in chat history,
        -- as specified by the Kong admins
        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              },
              {
                "role": "user",
                "content": "Tell me something about Amazon"
              },
              {
                "role": "assistant",
                "content": "Amazon is a tech company."
              },
              {
                "role": "user",
                "content": "Tell me more things about Amazon"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(400)
    end)

  end)
end
