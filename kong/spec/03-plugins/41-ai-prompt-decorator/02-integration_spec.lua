local helpers = require("spec.helpers")
local cjson   = require("cjson")


local PLUGIN_NAME = "ai-prompt-decorator"


local openai_flat_chat = {
  messages = {
    {
      role = "user",
      content = "I think that cheddar is the best cheese.",
    },
    {
      role = "assistant",
      content = "No, brie is the best cheese.",
    },
    {
      role = "user",
      content = "Why brie?",
    },
  },
}


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME, "ctx-checker-last", "ctx-checker" })


      -- echo route, we don't need a mock AI here
      local prepend = bp.routes:insert({
        hosts = { "prepend.decorate.local" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = prepend.id },
        config = {
          prompts = {
            prepend = {
              [1] = {
                role = "system",
                content = "Prepend text 1 here.",
              },
              [2] = {
                role = "system",
                content = "Prepend text 2 here.",
              },
            },
          },
        },
      }

      bp.plugins:insert {
        name = "ctx-checker-last",
        route = { id = prepend.id },
        config = {
          ctx_check_field = "ai_namespaced_ctx",
        }
      }


      local append = bp.routes:insert({
        hosts = { "append.decorate.local" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = append.id },
        config = {
          prompts = {
            append = {
              [1] = {
                role = "assistant",
                content = "Append text 1 here.",
              },
              [2] = {
                role = "user",
                content = "Append text 2 here.",
              },
            },
          },
        },
      }

      bp.plugins:insert {
        name = "ctx-checker-last",
        route = { id = append.id },
        config = {
          ctx_check_field = "ai_namespaced_ctx",
        }
      }

      local both = bp.routes:insert({
        hosts = { "both.decorate.local" },
      })

      
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = both.id },
        config = {
          prompts = {
            prepend = {
              [1] = {
                role = "system",
                content = "Prepend text 1 here.",
              },
              [2] = {
                role = "assistant",
                content = "Prepend text 2 here.",
              },
            },
            append = {
              [1] = {
                role = "assistant",
                content = "Append text 3 here.",
              },
              [2] = {
                role = "user",
                content = "Append text 4 here.",
              },
            },
          },
        },
      }

      bp.plugins:insert {
        name = "ctx-checker-last",
        route = { id = both.id },
        config = {
          ctx_check_field = "ai_namespaced_ctx",
        }
      }


      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled,ctx-checker-last,ctx-checker," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
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

    describe("request", function()
      it("modifies the LLM chat request - prepend", function()
        local r = client:get("/", {
          headers = {
            host = "prepend.decorate.local",
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode(openai_flat_chat),
        })

        -- get the REQUEST body, that left Kong for the upstream, using the echo system
        assert.response(r).has.status(200)
        local request = assert.response(r).has.jsonbody()
        request = cjson.decode(request.post_data.text)

        assert.same({ content = "Prepend text 1 here.", role = "system" }, request.messages[1])
        assert.same({ content = "Prepend text 2 here.", role = "system" }, request.messages[2])

        -- check ngx.ctx was set properly for later AI chain filters
        local ctx = assert.response(r).has.header("ctx-checker-last-ai-namespaced-ctx")
        ctx = ngx.unescape_uri(ctx)
        assert.match_re(ctx, [[.*decorate-prompt.*]])
        assert.match_re(ctx, [[.*decorated = true.*]])
        assert.match_re(ctx, [[.*Prepend text 1 here.*]])
        assert.match_re(ctx, [[.*Prepend text 2 here.*]])
      end)

      it("modifies the LLM chat request - append", function()
        local r = client:get("/", {
          headers = {
            host = "append.decorate.local",
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode(openai_flat_chat),
        })

        -- get the REQUEST body, that left Kong for the upstream, using the echo system
        assert.response(r).has.status(200)
        local request = assert.response(r).has.jsonbody()
        request = cjson.decode(request.post_data.text)

        assert.same({ content = "Append text 1 here.", role = "assistant" }, request.messages[#request.messages-1])
        assert.same({ content = "Append text 2 here.", role = "user" }, request.messages[#request.messages])

        -- check ngx.ctx was set properly for later AI chain filters
        local ctx = assert.response(r).has.header("ctx-checker-last-ai-namespaced-ctx")
        ctx = ngx.unescape_uri(ctx)
        assert.match_re(ctx, [[.*decorate-prompt.*]])
        assert.match_re(ctx, [[.*decorated = true.*]])
        assert.match_re(ctx, [[.*Append text 1 here.*]])
        assert.match_re(ctx, [[.*Append text 2 here.*]])
      end)


      it("modifies the LLM chat request - both", function()
        local r = client:get("/", {
          headers = {
            host = "both.decorate.local",
            ["Content-Type"] = "application/json"
          },
          body = cjson.encode(openai_flat_chat),
        })

        -- get the REQUEST body, that left Kong for the upstream, using the echo system
        assert.response(r).has.status(200)
        local request = assert.response(r).has.jsonbody()
        request = cjson.decode(request.post_data.text)

        assert.same({ content = "Prepend text 1 here.", role = "system" }, request.messages[1])
        assert.same({ content = "Prepend text 2 here.", role = "assistant" }, request.messages[2])
        assert.same({ content = "Append text 3 here.", role = "assistant" }, request.messages[#request.messages-1])
        assert.same({ content = "Append text 4 here.", role = "user" }, request.messages[#request.messages])

        -- check ngx.ctx was set properly for later AI chain filters
        local ctx = assert.response(r).has.header("ctx-checker-last-ai-namespaced-ctx")
        ctx = ngx.unescape_uri(ctx)
        assert.match_re(ctx, [[.*decorate-prompt.*]])
        assert.match_re(ctx, [[.*decorated = true.*]])
        assert.match_re(ctx, [[.*Prepend text 1 here.*]])
        assert.match_re(ctx, [[.*Prepend text 2 here.*]])
        assert.match_re(ctx, [[.*Append text 3 here.*]])
        assert.match_re(ctx, [[.*Append text 4 here.*]])
      end)
    end)
  end)

end end
