-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cycle_aware_deep_copy = require "kong.tools.table".cycle_aware_deep_copy
local ai_plugin_ctx = require("kong.llm.plugin.ctx")
local ai_plugin_o11y = require("kong.llm.plugin.observability")
local ai_shared = require("kong.llm.drivers.shared")
local llm = require("kong.llm")

local _M = {
  NAME = "normalize-request",
  STAGE = "REQ_TRANSFORMATION",
  DESCRIPTION = "transform the request body into a format suitable for the AI model",
}

local FILTER_OUTPUT_SCHEMA = {
  model = "table",
  route_type = "string",
  request_body_table = "table",
}

local _, set_ctx = ai_plugin_ctx.get_namespaced_accesors(_M.NAME, FILTER_OUTPUT_SCHEMA)
local get_global_ctx, set_global_ctx = ai_plugin_ctx.get_global_accessors(_M.NAME)


local _KEYBASTION = setmetatable({}, {
  __mode = "k",
  __index = ai_shared.cloud_identity_function,
})

local function bail(code, msg)
  if code == 400 and msg then
    kong.log.info(msg)
  end

  if ngx.get_phase() ~= "balancer" then
    return kong.response.exit(code, msg and { error = { message = msg } } or nil)
  end
end

local function copy_request_table(request_table)
  -- only copy the "options", to save memory, as messages are not overriden
  local new_t = {}
  for k, v in pairs(request_table) do
    if k ~= "messages" then
      new_t[k] = cycle_aware_deep_copy(v)
    end
  end

  -- TODO: make messsages immutable
  new_t.messages = request_table.messages

  return new_t
end

-- TODO: split validate and transform
local function validate_and_transform(conf)
  if not conf.model then
    error("conf.model missing from plugin configuration", 2)
  end

  -- TODO: refactor the ai_shared module to seperate the model options from other plugin conf
  -- by using the `namespaced_ctx.model`
  local conf_m, err = ai_shared.merge_model_options(kong.request, conf)
  if err then
    return bail(400, err)
  end

  local model_t = conf_m.model
  local model_provider = conf.model.provider -- use the one from conf, not the merged one to avoid potential security risk

  local request_table = ai_plugin_ctx.get_namespaced_ctx("parse-request", "request_body_table")
  if not request_table then
    return bail(400, "no request body found when transforming request")
  end

  -- duplicate it, to avoid our mutation of the table poplute the original parsed request
  -- TODO: a proper func to skip copying request_table.messages but keep others
  request_table = copy_request_table(request_table)
  set_ctx("request_body_table", request_table)

  -- copy from the user request if present
  if (not model_t.name) and (request_table.model) then
    if type(request_table.model) == "string" then
      model_t.name = request_table.model
    end
  end

  -- check that the user isn't trying to override the plugin conf model in the request body
  if request_table.model and type(request_table.model) == "string" and request_table.model ~= "" then
    if request_table.model ~= model_t.name then
      return bail(400, "cannot use own model - must be: " .. model_t.name)
    end
  end

  -- model is stashed in the copied plugin conf, for consistency in transformation functions
  if not model_t.name then
    return bail(400, "model parameter not found in request, nor in gateway configuration")
  end

  set_ctx("model", model_t)

  -- store the route_type in ctx for use in response parsing
  local route_type = conf.route_type
  set_ctx("route_type", route_type)

  local multipart = ai_plugin_ctx.get_namespaced_ctx("parse-request", "multipart_request")
  -- check the incoming format is the same as the configured LLM format
  local compatible, err = llm.is_compatible(request_table, route_type)
  if not multipart and not compatible then
    return bail(400, err)
  end

  -- check if the user has asked for a stream, and/or if
  -- we are forcing all requests to be of streaming type
  if request_table and request_table.stream or
     (conf.response_streaming and conf.response_streaming == "always") then
    request_table.stream = true

    -- this condition will only check if user has tried
    -- to activate streaming mode within their request
    if conf.response_streaming and conf.response_streaming == "deny" then
      return bail(400, "response streaming is not enabled for this LLM")
    end

    -- specific actions need to skip later for this to work
    set_global_ctx("stream_mode", true)

  else
    kong.service.request.enable_buffering()

    set_global_ctx("stream_mode", false)
  end

  local ai_driver = require("kong.llm.drivers." .. conf.model.provider)

  -- execute pre-request hooks for this driver
  local ok, err = ai_driver.pre_request(conf_m, request_table)
  if not ok then
    return bail(400, err)
  end

  -- transform the body to Kong-format for this provider/model
  local parsed_request_body, content_type, err
  if route_type ~= "preserve" and (not multipart) then
    -- transform the body to Kong-format for this provider/model
    parsed_request_body, content_type, err = ai_driver.to_format(request_table, model_t, route_type)
    if err then
      return bail(400, err)
    end
  end

   -- process form/json body auth information
   local auth_param_name = conf.auth and conf.auth.param_name
   local auth_param_value = conf.auth and conf.auth.param_value
   local auth_param_location = conf.auth and conf.auth.param_location

   if auth_param_name and auth_param_value and auth_param_location == "body" and request_table then
     if request_table[auth_param_name] == nil or not conf.auth.allow_override then
       request_table[auth_param_name] = auth_param_value
     end
   end

  -- store token cost estimate, on first pass, if the
  -- provider doesn't reply with a prompt token count
  if not ai_shared.streaming_has_token_counts[model_provider] then
    local cost = get_global_ctx("stream_mode") and 1.8 or 1.0
    local prompt_tokens, err = ai_shared.calculate_cost(request_table or {}, {}, cost)
    if err then
      kong.log.err("unable to estimate request token cost: ", err)
      return bail(500)
    end

    ai_plugin_o11y.metrics_set("llm_prompt_tokens_count", prompt_tokens)
  end

  if route_type ~= "preserve" and ngx.get_phase() ~= "balancer" then
    kong.service.request.set_body(parsed_request_body, content_type)
  end

  -- get the provider's cached identity interface - nil may come back, which is fine
  local identity_interface = _KEYBASTION[conf]

  if identity_interface and identity_interface.error then
    kong.log.err("error authenticating with ", model_provider, " using native provider auth, ", identity_interface.error)
    return bail(500, "LLM request failed before proxying")
  end

  -- now re-configure the request for this operation type
  local ok, err = ai_driver.configure_request(conf_m,
               identity_interface and identity_interface.interface)
  if not ok then
    kong.log.err("failed to configure request for AI service: ", err)
    return bail(500)
  end

  -- lights out, and away we go
end


function _M:run(conf)
  if ai_plugin_ctx.has_namespace("ai-proxy-advanced-balance") then
    conf = ai_plugin_ctx.get_namespaced_ctx("ai-proxy-advanced-balance", "selected_target") or conf
  end

  validate_and_transform(conf)

  return true
end

return _M