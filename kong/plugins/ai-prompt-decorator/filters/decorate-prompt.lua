-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local new_tab = require("table.new")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")

local _M = {
  NAME = "decorate-prompt",
  STAGE = "REQ_TRANSFORMATION",
  }

local FILTER_OUTPUT_SCHEMA = {
  decorated = "boolean",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

local EMPTY = {}


local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end


-- Adds the prompts to the request prepend/append.
-- @tparam table request The deserialized JSON body of the request
-- @tparam table conf The plugin configuration
-- @treturn table The decorated request (same table, content updated)
local function execute(request, conf)
  local prepend = conf.prompts.prepend or EMPTY
  local append = conf.prompts.append or EMPTY

  local old_messages = request.messages
  local new_messages = new_tab(#append + #prepend + #old_messages, 0)
  request.messages = new_messages

  local n = 0

  for _, msg in ipairs(prepend) do
    n = n + 1
    new_messages[n] = { role = msg.role, content = msg.content }
  end

  for _, msg in ipairs(old_messages) do
    n = n + 1
    new_messages[n] = msg
  end

  for _, msg in ipairs(append) do
    n = n + 1
    new_messages[n] = { role = msg.role, content = msg.content }
  end

  return request
end

if _G._TEST then
  -- only if we're testing export this function (using a different name!)
  _M._execute = execute
end


function _M:run(conf)
  -- if plugin ordering was altered, receive the "decorated" request
  local request_body_table = ai_plugin_ctx.get_request_body_table_inuse()
  if not request_body_table then
    return bad_request("this LLM route only supports application/json requests")
  end

  if #(request_body_table.messages or EMPTY) < 1 then
    return bad_request("this LLM route only supports llm/chat type requests")
  end

  kong.service.request.set_body(execute(request_body_table, conf), "application/json")

  set_ctx("decorated", true)

  return true
end

return _M