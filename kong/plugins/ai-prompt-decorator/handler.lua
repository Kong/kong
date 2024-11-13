local new_tab = require("table.new")
local llm_state = require("kong.llm.state")
local EMPTY = {}


local plugin = {
  PRIORITY = 772,
  VERSION = require("kong.meta").version
}



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



function plugin:access(conf)
  kong.service.request.enable_buffering()
  llm_state.set_prompt_decorated()  -- future use

  -- if plugin ordering was altered, receive the "decorated" request
  local request = kong.request.get_body("application/json", nil, conf.max_request_body_size)
  if type(request) ~= "table"  then
    return bad_request("this LLM route only supports application/json requests")
  end

  if #(request.messages or EMPTY) < 1 then
    return bad_request("this LLM route only supports llm/chat type requests")
  end

  kong.service.request.set_body(execute(request, conf), "application/json")
end



if _G._TEST then
  -- only if we're testing export this function (using a different name!)
  plugin._execute = execute
end


return plugin
