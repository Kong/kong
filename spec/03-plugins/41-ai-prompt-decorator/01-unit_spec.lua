local PLUGIN_NAME = "ai-prompt-decorator"

-- imports
local access_handler = require("kong.plugins.ai-prompt-decorator.handler")
--

local function deepcopy(o, seen)
  seen = seen or {}
  if o == nil then return nil end
  if seen[o] then return seen[o] end

  local no
  if type(o) == 'table' then
    no = {}
    seen[o] = no

    for k, v in next, o, nil do
      no[deepcopy(k, seen)] = deepcopy(v, seen)
    end
    setmetatable(no, deepcopy(getmetatable(o), seen))
  else -- number, string, boolean, etc
    no = o
  end
  return no
end

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
    [3] = {
      role = "assistant",
      content = "The answer is 2?"
    },
    [4] = {
      role = "user",
      content = "Now double it."
    },
  },
}

local injector_conf_prepend = {
  prompts = {
    prepend = {
      [1] = {
        role = "system",
        content = "Give me answers in French language."
      },
      [2] = {
        role = "user",
        content = "Consider you are a mathematician."
      },
      [3] = {
        role = "assistant",
        content = "Okay I am a mathematician. What is your maths question?"
      },
    },
  },
}

local injector_conf_append = {
  prompts = {
    append = {
      [1] = {
        role = "system",
        content = "Give me answers in French language."
      },
      [2] = {
        role = "system",
        content = "Give me the answer in JSON format."
      },
    },
  },
}

local injector_conf_both = {
  prompts = {
    prepend = {
      [1] = {
        role = "system",
        content = "Give me answers in French language."
      },
      [2] = {
        role = "user",
        content = "Consider you are a mathematician."
      },
      [3] = {
        role = "assistant",
        content = "Okay I am a mathematician. What is your maths question?"
      },
    },
    append = {
      [1] = {
        role = "system",
        content = "Give me answers in French language."
      },
      [2] = {
        role = "system",
        content = "Give me the answer in JSON format."
      },
    },
  },
}

describe(PLUGIN_NAME .. ": (unit)", function()

  describe("chat v1 operations", function()

    it("adds messages to the start of the array", function()
      local request_copy = deepcopy(general_chat_request)
      local expected_request_copy = deepcopy(general_chat_request)

      -- combine the tables manually, and check the code does the same
      table.insert(expected_request_copy.messages, 1, injector_conf_prepend.prompts.prepend[1])
      table.insert(expected_request_copy.messages, 2, injector_conf_prepend.prompts.prepend[2])
      table.insert(expected_request_copy.messages, 3, injector_conf_prepend.prompts.prepend[3])

      local decorated_request, err = access_handler.execute(request_copy, injector_conf_prepend)

      assert.is_nil(err)
      assert.same(decorated_request, expected_request_copy)
    end)

    it("adds messages to the end of the array", function()
      local request_copy = deepcopy(general_chat_request)
      local expected_request_copy = deepcopy(general_chat_request)

      -- combine the tables manually, and check the code does the same
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_append.prompts.append[1])
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_append.prompts.append[2])

      local decorated_request, err = access_handler.execute(request_copy, injector_conf_append)

      assert.is_nil(err)
      assert.same(expected_request_copy, decorated_request)
    end)

    it("adds messages to the start and the end of the array", function()
      local request_copy = deepcopy(general_chat_request)
      local expected_request_copy = deepcopy(general_chat_request)

      -- combine the tables manually, and check the code does the same
      table.insert(expected_request_copy.messages, 1, injector_conf_both.prompts.prepend[1])
      table.insert(expected_request_copy.messages, 2, injector_conf_both.prompts.prepend[2])
      table.insert(expected_request_copy.messages, 3, injector_conf_both.prompts.prepend[3])
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_both.prompts.append[1])
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_both.prompts.append[2])

      local decorated_request, err = access_handler.execute(request_copy, injector_conf_both)

      assert.is_nil(err)
      assert.same(expected_request_copy, decorated_request)
    end)

  end)

end)
