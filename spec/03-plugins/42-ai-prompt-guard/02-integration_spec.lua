local helpers = require "spec.helpers"

local PLUGIN_NAME = "ai-prompt-guard"


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (access) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()

      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })

      -- both
      local permit_history = bp.routes:insert({
        paths = { "~/permit-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = permit_history.id },
        config = {
          allow_patterns = {
            [1] = ".*cheddar.*",
            [2] = ".*brie.*",
          },
          deny_patterns = {
            [1] = ".*leicester.*",
            [2] = ".*edam.*",
          },
          allow_all_conversation_history = true,
        },
      }

      local block_history = bp.routes:insert({
        paths = { "~/block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history.id },
        config = {
          allow_patterns = {
            [1] = ".*cheddar.*",
            [2] = ".*brie.*",
          },
          deny_patterns = {
            [1] = ".*leicester.*",
            [2] = ".*edam.*",
          },
          allow_all_conversation_history = false,
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
          allow_patterns = {
            [1] = ".*cheddar.*",
            [2] = ".*brie.*",
          },
          allow_all_conversation_history = true,
        },
      }

      local block_history_allow_only = bp.routes:insert({
        paths = { "~/allow-only-block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history_allow_only.id },
        config = {
          allow_patterns = {
            [1] = ".*cheddar.*",
            [2] = ".*brie.*",
          },
          allow_all_conversation_history = false,
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
          deny_patterns = {
            [1] = ".*leicester.*",
            [2] = ".*edam.*",
          },
          allow_all_conversation_history = true,
        },
      }

      local block_history_deny_only = bp.routes:insert({
        paths = { "~/deny-only-block-history$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = block_history_deny_only.id },
        config = {
          deny_patterns = {
            [1] = ".*leicester.*",
            [2] = ".*edam.*",
          },
          allow_all_conversation_history = false,
        },
      }
      --

      local bad_regex_allow = bp.routes:insert({
        paths = { "~/bad-regex-allow$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = bad_regex_allow.id },
        config = {
          deny_patterns = {
            [1] = "[]",
          },
          allow_all_conversation_history = false,
        },
      }

      local bad_regex_deny = bp.routes:insert({
        paths = { "~/bad-regex-deny$" },
      })

      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = bad_regex_deny.id },
        config = {
          deny_patterns = {
            [1] = "[]",
          },
          allow_all_conversation_history = false,
        },
      }

      --
      assert(helpers.start_kong({
        database   = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
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
                "content": "I think that cheddar is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, brie is the best cheese."
              },
              {
                "role": "user",
                "content": "Why brie?"
              }
            ]
          }
        ]],
        method = "POST",
      })

      -- the body is just an echo, don't need to test it
      assert.response(r).has.status(200)
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
                "content": "I think that cheddar is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, brie is the best cheese."
              },
              {
                "role": "user",
                "content": "Why brie?"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(200)
    end)


    it("blocks message with 'allow' and 'deny' set, with history", function()
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
                "content": "I think that cheddar or edam are the best cheeses."
              },
              {
                "role": "assistant",
                "content": "No, brie is the best cheese."
              },
              {
                "role": "user",
                "content": "Why?"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(400)
    end)
    --


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
                "content": "I think that brie is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, cheddar is the best cheese."
              },
              {
                "role": "user",
                "content": "Why cheddar?"
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
                "content": "I think that brie is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, cheddar is the best cheese."
              },
              {
                "role": "user",
                "content": "Why cheddar?"
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
                "content": "I think that leicester is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, cheddar is the best cheese."
              },
              {
                "role": "user",
                "content": "Why cheddar?"
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
                "content": "I think that leicester is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, edam is the best cheese."
              },
              {
                "role": "user",
                "content": "Why edam?"
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
                "content": "I think that leicester is the best cheese."
              },
              {
                "role": "assistant",
                "content": "No, cheddar is the best cheese."
              },
              {
                "role": "user",
                "content": "Why cheddar?"
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(400)
    end)


    it("returns a 500 on a bad regex in allow list", function()
      local r = client:get("/bad-regex-allow", {
        headers = {
          ["Content-Type"] = "application/json",
        },

        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(500)
    end)


    it("returns a 500 on a bad regex in deny list", function()
      local r = client:get("/bad-regex-deny", {
        headers = {
          ["Content-Type"] = "application/json",
        },

        body = [[
          {
            "messages": [
              {
                "role": "system",
                "content": "You run a cheese shop."
              }
            ]
          }
        ]],
        method = "POST",
      })

      assert.response(r).has.status(500)
    end)

  end)

end end
