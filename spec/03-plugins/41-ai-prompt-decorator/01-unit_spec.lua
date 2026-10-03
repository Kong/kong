local PLUGIN_NAME = "ai-prompt-decorator"


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

  local access_handler

  setup(function()
    _G._TEST = true
    package.loaded["kong.plugins.ai-prompt-decorator.filters.decorate-prompt"] = nil
    access_handler = require("kong.plugins.ai-prompt-decorator.filters.decorate-prompt")
  end)

  teardown(function()
    _G._TEST = nil
  end)



  describe("chat v1 operations", function()

    it("adds messages to the start of the array", function()
      local request_copy = deepcopy(general_chat_request)
      local expected_request_copy = deepcopy(general_chat_request)

      -- combine the tables manually, and check the code does the same
      table.insert(expected_request_copy.messages, 1, injector_conf_prepend.prompts.prepend[1])
      table.insert(expected_request_copy.messages, 2, injector_conf_prepend.prompts.prepend[2])
      table.insert(expected_request_copy.messages, 3, injector_conf_prepend.prompts.prepend[3])

      local decorated_request, err = access_handler._execute(request_copy, injector_conf_prepend)

      assert.is_nil(err)
      assert.same(decorated_request, expected_request_copy)
    end)


    it("adds messages to the end of the array", function()
      local request_copy = deepcopy(general_chat_request)
      local expected_request_copy = deepcopy(general_chat_request)

      -- combine the tables manually, and check the code does the same
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_append.prompts.append[1])
      table.insert(expected_request_copy.messages, #expected_request_copy.messages + 1, injector_conf_append.prompts.append[2])

      local decorated_request, err = access_handler._execute(request_copy, injector_conf_append)

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

      local decorated_request, err = access_handler._execute(request_copy, injector_conf_both)

      assert.is_nil(err)
      assert.same(expected_request_copy, decorated_request)
    end)

  end)

  describe("empty JSON arrays (#14983)", function()
    local cjson
    local ai_plugin_ctx

    setup(function()
      cjson = require("kong.tools.cjson")
      ai_plugin_ctx = require("kong.llm.plugin.ctx")
    end)

    it("keeps empty tools and nested required arrays after decorate + encode", function()
      local request = {
        messages = {
          { role = "user", content = "ping" },
        },
        tools = cjson.decode_with_array_mt("[]"),
        extra = {
          required = cjson.decode_with_array_mt("[]"),
        },
      }

      local immutable = ai_plugin_ctx.immutable_table(request)
      local materialized = access_handler._materialize_request(immutable)
      local decorated, err = access_handler._execute(materialized, injector_conf_prepend)
      assert.is_nil(err)

      local encoded, encode_err = access_handler._encode_request_body(decorated)
      assert.is_nil(encode_err)
      assert.matches('"tools":%s*%[%]', encoded)
      assert.matches('"required":%s*%[%]', encoded)
      assert.not_matches('"tools":%s*{}', encoded)
      assert.not_matches('"required":%s*{}', encoded)
    end)
  end)

end)
