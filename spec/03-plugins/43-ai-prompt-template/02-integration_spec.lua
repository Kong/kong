local helpers = require "spec.helpers"
local cjson   = require "cjson"

local PLUGIN_NAME = "ai-prompt-template"



for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      local route1 = bp.routes:insert({
        hosts = { "test1.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          templates = {
            [1] = {
              name = "developer-chat",
              template = [[
                {
                  "messages": [
                    {
                      "role": "system",
                      "content": "You are a {{program}} expert, in {{language}} programming language."
                    },
                    {
                      "role": "user",
                      "content": "Write me a {{program}} program."
                    }
                  ]
                }
              ]],
            },
            [2] = {
              name = "developer-completions",
              template = [[
                {
                  "prompt": "You are a {{language}} programming expert. Make me a {{program}} program."
                }
              ]],
            },
          },
        },
      }

      local route2 = bp.routes:insert({
        hosts = { "test2.com" },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route2.id },
        config = {
          allow_untemplated_requests = false,
          templates = {
            [1] = {
              name = "developer-chat",
              template = [[
                {
                  "messages": [
                    {
                      "role": "system",
                      "content": "You are a {{program}} expert, in {{language}} programming language."
                    },
                    {
                      "role": "user",
                      "content": "Write me a {{program}} program."
                    }
                  ]
                }
              ]],
            },
            [2] = {
              name = "developer-completions",
              template = [[
                {
                  "prompt": "You are a {{language}} programming expert. Make me a {{program}} program."
                }
              ]],
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
      helpers.stop_kong()
    end)


    before_each(function()
      client = helpers.proxy_client()
    end)


    after_each(function()
      if client then client:close() end
    end)



    describe("request", function()

      it("templates a chat message", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://developer-chat}",
              "properties": {
                "language": "python",
                "program": "flask web server"
              }
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(200)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            messages = {
              [1] = {
                role = "system",
                content = "You are a flask web server expert, in python programming language."
              },
              [2] = {
                role = "user",
                content = "Write me a flask web server program."
              },
            }
          }, cjson.decode(json.post_data.text))
      end)


      it("templates a completions message", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://developer-completions}",
              "properties": {
                "language": "python",
                "program": "flask web server"
              }
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(200)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            prompt = "You are a python programming expert. Make me a flask web server program."
          }, cjson.decode(json.post_data.text))
      end)


      it("blocks when 'allow_untemplated_requests' is OFF", function()
        local r = client:get("/request", {
          headers = {
            host = "test2.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": [
                {
                  "role": "system",
                  "content": "Arbitrary content"
                }
              ]
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "this LLM route only supports templated requests"
            }
          }, json)
      end)


      it("doesn't block when 'allow_untemplated_requests' is ON", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": [
                {
                  "role": "system",
                  "content": "Arbitrary content"
                }
              ]
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(200)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            messages = {
              [1] = {
                role = "system",
                content = "Arbitrary content"
              }
            }
          }, json.post_data.params)
      end)


      it("errors with a not found template", function()
        local r = client:get("/request", {
          headers = {
            host = "test2.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://developer-doesnt-exist}",
              "properties": {
                "language": "python",
                "program": "flask web server"
              }
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "could not find template name [developer-doesnt-exist]"
            }
          }, json)
      end)


      it("still errors with a not found template when 'allow_untemplated_requests' is ON", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://not_found}"
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "could not find template name [not_found]"
            }
          }, json)
      end)


      it("errors with missing template parameter", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://developer-chat}",
              "properties": {
                "language": "python"
              }
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "missing template parameters: [program]"
            }
          }, json)
      end)


      it("errors with multiple missing template parameters", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[
            {
              "messages": "{template://developer-chat}",
              "properties": {
                "nothing": "no"
              }
            }
          ]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.matches("^missing template parameters: %[.*%], %[.*%]", json.error.message)
      end)


      it("fails with non-json request", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "text/plain",
          },
          body = [[template: programmer, property: hi]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "this LLM route only supports application/json requests"
            }
          }, json)
      end)


      it("fails with non llm/v1/chat or llm/v1/completions request", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[{
            "programmer": "hi"
          }]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "only 'llm/v1/chat' and 'llm/v1/completions' formats are supported for templating"
            }
          }, json)
      end)


      it("fails with multiple types of prompt", function()
        local r = client:get("/request", {
          headers = {
            host = "test1.com",
            ["Content-Type"] = "application/json",
          },
          body = [[{
            "messages": "{template://developer-chat}",
            "prompt": "{template://developer-prompt}",
            "properties": {
              "nothing": "no"
            }
          }]],
          method = "POST",
        })

        assert.response(r).has.status(400)
        local json = assert.response(r).has.jsonbody()

        assert.same({
            error = {
              message = "cannot run 'messages' and 'prompt' templates at the same time"
            }
          }, json)
      end)

    end)

  end)

end end
