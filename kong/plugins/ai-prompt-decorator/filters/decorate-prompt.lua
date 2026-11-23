local new_tab = require("table.new")
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local cycle_aware_deep_copy = require("kong.tools.table").cycle_aware_deep_copy
local cjson = require("kong.tools.cjson")

local _M = {
  NAME = "decorate-prompt",
  STAGE = "REQ_TRANSFORMATION",
}

local FILTER_OUTPUT_SCHEMA = {
  decorated = "boolean",
  request_body_table = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)

local EMPTY = {}


local function bad_request(msg)
  kong.log.info(msg)
  return kong.response.exit(400, { error = { message = msg } })
end


-- get_request_body_table_inuse() wraps the real body in an immutable proxy
-- (empty table + __index). cycle_aware_deep_copy of that proxy keeps the
-- proxy metatable and no own keys, so cjson encodes it as {}.
-- Copy the underlying table so array_mt on empty JSON arrays survives.
local function materialize_request(request)
  local mt = getmetatable(request)
  if mt and type(mt.__index) == "table" then
    request = mt.__index
  end
  return cycle_aware_deep_copy(request)
end


local function encode_request_body(request)
  return cjson.encode(request)
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
  _M._materialize_request = materialize_request
  _M._encode_request_body = encode_request_body
end


function _M:run(conf)
  -- if plugin ordering was altered, receive the "decorated" request
  local request_body_table, source = ai_plugin_ctx.get_request_body_table_inuse()
  if not request_body_table then
    return bad_request("this LLM route only supports application/json requests")
  end

  kong.log.debug("using request body from source: ", source)

  if #(request_body_table.messages or EMPTY) < 1 then
    return bad_request("this LLM route only supports llm/chat type requests")
  end

  -- Deep copy to avoid modifying the immutable table.
  -- Re-assign it to trigger GC of the old one and save memory.
  request_body_table = execute(materialize_request(request_body_table), conf)

  local encoded, err = encode_request_body(request_body_table)
  if not encoded then
    return bad_request(err or "failed to encode decorated request")
  end

  -- set_body uses a cjson instance that turns empty tables without array_mt
  -- into {}. Encode with kong.tools.cjson so empty JSON arrays stay arrays.
  kong.service.request.set_raw_body(encoded)

  set_ctx("decorated", true)
  ai_plugin_ctx.set_request_body_table_inuse(request_body_table, _M.NAME)

  return true
end

return _M
