local PLUGIN_NAME = "ai-prompt-guard"

local message_fixtures = {
  user = "this is a user request",
  system = "this is a system message",
  assistant = "this is an assistant reply",
}

local _M = {}
local function create_request(typ)
  local messages = {
    {
      role = "system",
      content = message_fixtures.system,
    }
  }

  if typ ~= "chat" and typ ~= "completions" then
    error("type must be one of 'chat' or 'completions'", 2)
  end

  return setmetatable({
    messages = messages,
    type = typ,
  }, {
    __index = _M,
  })
end

function _M:append_message(role, custom)
  if not message_fixtures[role] then
    assert("role must be one of: user, system or assistant")
  end

  if self.type == "completion" then
    self.prompt = "this is a completions request"
    if custom then
      self.prompt = self.prompt .. " with custom content " .. custom
    end
    return
  end

  local message = message_fixtures[role]
  if custom then
    message = message .. " with custom content " .. custom
  end

  self.messages[#self.messages+1] = {
    role = "user",
    content = message
  }

  return self
end


describe(PLUGIN_NAME .. ": (unit)", function()

  local access_handler

  setup(function()
    _G._TEST = true
    package.loaded["kong.plugins.ai-prompt-guard.handler"] = nil
    access_handler = require("kong.plugins.ai-prompt-guard.handler")
  end)

  teardown(function()
    _G._TEST = nil
  end)



  for _, request_type in ipairs({"chat", "completions"}) do

    describe(request_type .. " operations", function()
      it("allows a user request when nothing is set", function()
        -- deny_pattern in this case should be made to have no effect
        local ctx = create_request(request_type):append_message("user", "pattern")
        local ok, err = access_handler._execute(ctx, {
        })

        assert.is_truthy(ok)
        assert.is_nil(err)
      end)

      -- only chat has history
      -- match_all_roles require history
      for _, has_history in ipairs({false, request_type == "chat" and true or nil}) do
      for _, match_all_roles in ipairs({false, has_history and true or nil}) do

        -- we only have user or not user, so testing "assistant" is not necessary
        local role = match_all_roles and "system" or "user"

        describe("conf.allow_patterns is set", function()
          for _, has_deny_patterns in ipairs({true, false}) do

            local test_description = has_history and " in history" or " only the last"
            test_description = test_description .. (has_deny_patterns and ", conf.deny_patterns is also set" or "")

            it("allows a matching user request" .. test_description, function()
              -- deny_pattern in this case should be made to have no effect
              local ctx = create_request(request_type):append_message(role, "pattern")

              if has_history then
                ctx:append_message("user", "no match")
              end
              local ok, err = access_handler._execute(ctx, {
                allow_patterns = {
                  "pa..ern"
                },
                deny_patterns = has_deny_patterns and {"deny match"} or nil,
                allow_all_conversation_history = not has_history,
                match_all_roles = match_all_roles,
              })

              assert.is_truthy(ok)
              assert.is_nil(err)
            end)

            it("denies an unmatched user request" .. test_description, function()
              -- deny_pattern in this case should be made to have no effect
              local ctx = create_request(request_type):append_message("user", "no match")

              if has_history then
                ctx:append_message("user", "no match")
              else
                -- if we are ignoring history, actually put a matched message in history to test edge case
                ctx:append_message(role, "pattern"):append_message("user", "no match")
              end

              local ok, err = access_handler._execute(ctx, {
                allow_patterns = {
                  "pa..ern"
                },
                deny_patterns = has_deny_patterns and {"deny match"} or nil,
                allow_all_conversation_history = not has_history,
                match_all_roles = match_all_roles,
              })

              assert.is_falsy(ok)
              assert.equal("prompt doesn't match any allowed pattern", err)
            end)

          end -- for _, has_deny_patterns in ipairs({true, false}) do
        end)

        describe("conf.deny_patterns is set", function()
          for _, has_allow_patterns in ipairs({true, false}) do

            local test_description = has_history and " in history" or " only the last"
            test_description = test_description .. (has_allow_patterns and ", conf.allow_patterns is also set" or "")

            it("denies a matching user request" .. test_description, function()
              -- allow_pattern in this case should be made to have no effect
              local ctx = create_request(request_type):append_message(role, "pattern")

              if has_history then
                ctx:append_message("user", "no match")
              end
              local ok, err = access_handler._execute(ctx, {
                deny_patterns = {
                  "pa..ern"
                },
                allow_patterns = has_allow_patterns and {"allow match"} or nil,
                allow_all_conversation_history = not has_history,
              })

              assert.is_falsy(ok)
              assert.equal("prompt pattern is blocked", err)
            end)

            it("allows unmatched user request" .. test_description, function()
              -- allow_pattern in this case should be made to have no effect
              local ctx = create_request(request_type):append_message(role, "allow match")

              if has_history then
                ctx:append_message("user", "no match")
              else
                -- if we are ignoring history, actually put a matched message in history to test edge case
                ctx:append_message(role, "pattern"):append_message(role, "allow match")
              end

              local ok, err = access_handler._execute(ctx, {
                deny_patterns = {
                  "pa..ern"
                },
                allow_patterns = has_allow_patterns and {"allow match"} or nil,
                allow_all_conversation_history = not has_history,
              })

              assert.is_truthy(ok)
              assert.is_nil(err)
            end)
          end -- for for _, has_allow_patterns in ipairs({true, false}) do
        end)

      end -- for _, match_all_role in ipairs(false, true)) do
      end -- for _, has_history in ipairs({true, false}) do
    end)
  end --   for _, request_type in ipairs({"chat", "completions"}) do

end)
