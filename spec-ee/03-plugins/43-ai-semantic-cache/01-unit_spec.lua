-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "ai-semantic-cache"
local llm_state = require "kong.llm.state"

local samples = {
  ["llm/v1/chat"] = {
    ["valid"] = {
      messages = {
        {
          role = "system",
          content = "You are a mathematician."
        },
        {
          role = "user",
          content = "What is Pi?"
        },
        {
          role = "assistant",
          content = "Pi (π) is a mathematical constant that represents the ratio of a circle's circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159."
        },
        {
          role = "user",
          content = "What is 2π?"
        },
      },
      usage = {
        prompt_tokens = 10,
        completion_tokens = 20,
        total_tokens = 30,
      },
    },
    ["invalid_empty_messages"] = {
      messages = {},
    },
    ["invalid_wrong_format"] = {
      role = "user",
      content = "You are a mathematician, what is Pi?",
    },
  },
}

describe(PLUGIN_NAME .. ": (unit)", function()

  local access_handler

  setup(function()
    _G._TEST = true
    package.loaded["kong.plugins.ai-semantic-cache.handler"] = nil
  end)

  teardown(function()
    _G._TEST = nil
  end)

  before_each(function()
    _G._TEST = true
    _G.kong = {
        ctx = {
            shared = {},
            plugin = {},
        },
    }
    package.loaded["kong.plugins.ai-semantic-cache.handler"] = nil
    access_handler = require("kong.plugins.ai-semantic-cache.handler")
  end)

  after_each(function()
    _G._TEST = nil
    _G.kong = nil
    access_handler = nil
  end)

  describe("llm/v1/chat operations", function()
    it("test good analytics output", function()
      local this_conf, this_stats, this_cache_stats


      llm_state.set_ai_proxy_conf({
        __key__ = "plugins:kong-ai-proxy-1:123456",
        model = {
          provider = "openai",
        },
      })

      access_handler._set_ngx({
        now = function()
          return math.floor(ngx.now()) + 10
        end,
        update_time = function()
          return true
        end,
      })

      access_handler._set_ai_shared({
        post_request = function(conf, stats)
          this_conf = conf
          this_stats = stats
          return true
        end,
        stash_cache_stats = function(conf, stats)
          this_conf = conf
          this_cache_stats = stats
          return true
        end,
      })

      access_handler._stash_stats({
        vectordb = {
          driver = "redis",
        },
        embeddings = {
          model = {
            provider = "kong",
            name = "kong-model",
          },
        },
      }, math.floor(ngx.now()), 100)

      access_handler._post_request(samples["llm/v1/chat"]["valid"])

      assert.same(this_conf, {
        __key__ = "plugins:kong-ai-proxy-1:123456",
        model = {
          provider = "openai",
        },
      })

      assert.same({
        vector_db = "redis",
        embeddings_latency = 100000,
        embeddings_provider = "kong",
        embeddings_model = "kong-model",
        fetch_latency = 10000,
      }, this_cache_stats)

      assert.same({
        prompt_tokens = 10,
        completion_tokens = 20,
        total_tokens = 30,
      }, this_stats.usage)
    end)

    it("test message format recognition and validation", function()
      assert.is_truthy(access_handler._validate_incoming(samples["llm/v1/chat"]["valid"]))
      assert.is_falsy(access_handler._validate_incoming(samples["llm/v1/chat"]["invalid_empty_messages"]))
      assert.is_falsy(access_handler._validate_incoming(samples["llm/v1/chat"]["invalid_wrong_format"]))
    end)

    it("test chat truncation", function()
      local output

      -- test truncate to two messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 2, false, false)
      assert.same(output, 'What is Pi?\n\nsystem: You are a mathematician.\n\n')

      -- test discard system messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, true, false)
      assert.same(output, 'What is 2π?\n\nassistant: Pi (π) is a mathematical constant that represents the ratio of a circle\'s circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159.\n\nWhat is Pi?\n\n')

      -- test discard assistant messages
      output = access_handler._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, false, true)
      assert.same(output, 'What is 2π?\n\nWhat is Pi?\n\nsystem: You are a mathematician.\n\n')
    end)

  end)
end)
