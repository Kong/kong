-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local PLUGIN_NAME = "ai-semantic-cache"

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
  local search_cache

  setup(function()
    _G._TEST = true
    search_cache = require("kong.plugins.ai-semantic-cache.filters.search-cache")
  end)

  teardown(function()
    _G._TEST = nil
  end)

  before_each(function()
    _G.kong = {
        ctx = {
            shared = {},
            plugin = {},
        },
    }
  end)

  after_each(function()
    _G.kong = nil
  end)

  describe("llm/v1/chat operations", function()
    pending("test good analytics output", function()
    end)

    it("test chat truncation", function()
      local output

      -- test truncate to two messages
      output = search_cache._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 2, false, false)
      assert.same(output, 'user: What is 2π?\n\nassistant: Pi (π) is a mathematical constant that represents the ratio of a circle\'s circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159.\n\n')

      -- test discard system messages
      output = search_cache._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, true, false)
      assert.same(output, 'user: What is 2π?\n\nassistant: Pi (π) is a mathematical constant that represents the ratio of a circle\'s circumference to its diameter. This ratio is constant for all circles and is approximately equal to 3.14159.\n\nuser: What is Pi?\n\n')

      -- test discard assistant messages
      output = search_cache._format_chat(samples["llm/v1/chat"]["valid"]["messages"], 20, false, true)
      assert.same(output, 'user: What is 2π?\n\nuser: What is Pi?\n\nsystem: You are a mathematician.\n\n')
    end)

  end)
end)
