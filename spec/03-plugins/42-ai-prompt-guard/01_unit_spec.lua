local PLUGIN_NAME = "ai-prompt-guard"
local access_handler = require("kong.plugins.ai-prompt-guard.handler")


local general_chat_request = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "user",
      content = "What is 1 + 1?"
    },
  },
}

local general_chat_request_with_history = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "user",
      content = "What is 12 + 1?"
    },
    [3] = {
      role = "assistant",
      content = "The answer is 13.",
    },
    [4] = {
      role = "user",
      content = "Now double the previous answer.",
    },
  },
}

local denied_chat_request = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "user",
      content = "What is 22 + 1?"
    },
  },
}

local neither_allowed_nor_denied_chat_request = {
  messages = {
    [1] = {
      role = "system",
      content = "You are a mathematician."
    },
    [2] = {
      role = "user",
      content = "What is 55 + 55?"
    },
  },
}


local general_completions_request = {
  prompt = "You are a mathematician. What is 1 + 1?"
}


local denied_completions_request = {
  prompt = "You are a mathematician. What is 22 + 1?"
}

local neither_allowed_nor_denied_completions_request = {
  prompt = "You are a mathematician. What is 55 + 55?"
}

local allow_patterns_no_history = {
  allow_patterns = {
    [1] = ".*1 \\+ 1.*"
  },
  allow_all_conversation_history = true,
}

local allow_patterns_with_history = {
  allow_patterns = {
    [1] = ".*1 \\+ 1.*"
  },
  allow_all_conversation_history = false,
}

local deny_patterns_with_history = {
  deny_patterns = {
    [1] = ".*12 \\+ 1.*"
  },
  allow_all_conversation_history = false,
}

local deny_patterns_no_history = {
  deny_patterns = {
    [1] = ".*22 \\+ 1.*"
  },
  allow_all_conversation_history = true,
}

local both_patterns_no_history = {
  allow_patterns = {
    [1] = ".*1 \\+ 1.*"
  },
  deny_patterns = {
    [1] = ".*99 \\+ 99.*"
  },
  allow_all_conversation_history = true,
}

describe(PLUGIN_NAME .. ": (unit)", function()


  describe("chat operations", function()

    it("allows request when only conf.allow_patterns is set", function()
      local ok, err = access_handler.execute(general_chat_request, allow_patterns_no_history)

      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("allows request when only conf.deny_patterns is set, and pattern should not match", function()
      local ok, err = access_handler.execute(general_chat_request, deny_patterns_no_history)

      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("denies request when only conf.allow_patterns is set, and pattern should not match", function()
      local ok, err = access_handler.execute(denied_chat_request, allow_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt doesn't match any allowed pattern")
    end)

    it("denies request when only conf.deny_patterns is set, and pattern should match", function()
      local ok, err = access_handler.execute(denied_chat_request, deny_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt pattern is blocked")
    end)

    it("allows request when both conf.allow_patterns and conf.deny_patterns are set, and pattern matches allow", function()
      local ok, err = access_handler.execute(general_chat_request, both_patterns_no_history)

      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("denies request when both conf.allow_patterns and conf.deny_patterns are set, and pattern matches neither", function()
      local ok, err = access_handler.execute(neither_allowed_nor_denied_chat_request, both_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt doesn't match any allowed pattern")
    end)

    it("denies request when only conf.allow_patterns is set and previous chat history should not match", function()
      local ok, err = access_handler.execute(general_chat_request_with_history, allow_patterns_with_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt doesn't match any allowed pattern")
    end)

    it("denies request when only conf.deny_patterns is set and previous chat history should match", function()
      local ok, err = access_handler.execute(general_chat_request_with_history, deny_patterns_with_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt pattern is blocked")
    end)

  end)


  describe("completions operations", function()

    it("allows request when only conf.allow_patterns is set", function()
      local ok, err = access_handler.execute(general_completions_request, allow_patterns_no_history)

      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("allows request when only conf.deny_patterns is set, and pattern should not match", function()
      local ok, err = access_handler.execute(general_completions_request, deny_patterns_no_history)

      assert.is_truthy(ok)
      assert.is_nil(err)
    end)

    it("denies request when only conf.allow_patterns is set, and pattern should not match", function()
      local ok, err = access_handler.execute(denied_completions_request, allow_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt doesn't match any allowed pattern")
    end)

    it("denies request when only conf.deny_patterns is set, and pattern should match", function()
      local ok, err = access_handler.execute(denied_completions_request, deny_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal("prompt pattern is blocked", err)
    end)

    it("denies request when both conf.allow_patterns and conf.deny_patterns are set, and pattern matches neither", function()
      local ok, err = access_handler.execute(neither_allowed_nor_denied_completions_request, both_patterns_no_history)

      assert.is_falsy(ok)
      assert.equal(err, "prompt doesn't match any allowed pattern")
    end)

  end)


end)
