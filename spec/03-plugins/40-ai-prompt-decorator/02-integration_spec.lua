local helpers = require "spec.helpers"
local cjson   = require "cjson"

local PLUGIN_NAME = "ai-prompt-decorator"


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- Inject a test route. No need to create a service, there is a default
      -- service which will echo the request.
      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })
      -- add the plugin to test to the route we created
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
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
            append = {
              [1] = {
                role = "system",
                content = "Append text 1 here.",
              },
              [2] = {
                role = "system",
                content = "Append text 2 here.",
              },
            },
          },
        },
      }

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
      it("sends in a non-chat message", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "anything": [
                {
                  "random": "data"
                }
              ]
            }]],
          method = "POST",
        })
        
        local body = assert.res_status(400, r)
        local json = cjson.decode(body)

        assert.same(json, { error = true, message = "ai-prompt-decorator only support llm/chat type requests" })
      end)

      it("sends in an empty messages array", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": []
            }]],
          method = "POST",
        })
        
        local body = assert.res_status(400, r)
        local json = cjson.decode(body)

        assert.same(json, { error = true, message = "ai-prompt-decorator only support llm/chat type requests" })
      end)
    end)

  end)

end end
