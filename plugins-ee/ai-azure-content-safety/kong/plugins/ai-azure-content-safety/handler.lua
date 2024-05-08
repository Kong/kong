-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- imports
local meta = require("kong.meta")
local http = require("resty.http")
local cjson = require("cjson.safe")
local buffer = require("string.buffer")

-- local handles
local kong = kong
local table_insert = table.insert



local plugin = {
  PRIORITY = 774,
  VERSION = meta.core_version,
}



local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end



-- configcache is an interface that is loosely instantiated.
-- It will be tied to the instance of "plugin_conf" per-plugin,
-- and is used to separate instances of the Azure SDK interface
-- between plugin instances, and thus different token caches.
local clientcache = setmetatable({}, {
  __mode = "k",
  __index = function(clientcache, plugin_config)

    ngx.log(ngx.DEBUG, "loading azure sdk for ", plugin_config.content_safety_url)

    local azure_client = require("resty.azure"):new({
      client_id = plugin_config.azure_client_id,
      client_secret = plugin_config.azure_client_secret,
      tenant_id = plugin_config.azure_tenant_id,
      token_scope = "https://cognitiveservices.azure.com/.default",
      token_version = "v2.0",
    })

    local _, err = azure_client.authenticate()
    if err then
      ngx.log(ngx.ERR, "failed to authenticate with Azure Content Services, ", err)
      return kong.response.exit(500, { error = { message = "failed to authenticate with Azure Content Services" }})
    end

    -- store our item for the next time we need it
    clientcache[plugin_config] = azure_client
    return azure_client
  end,
})



-- separate cache for the configuration lists/sets
-- (due to tests, we can't use the same cache as above)
local configcache = setmetatable({}, {
  __mode = "k",
  __index = function(configcache, plugin_config)
    -- create array of category names
    local category_names = {}
    for _, v in pairs(plugin_config.categories) do
      table_insert(category_names, v.name)
    end

    -- gather our defined categories into a set
    local category_checks = {}
    for _, v in pairs(plugin_config.categories) do
      category_checks[v.name] = v.rejection_level
    end

    -- store our item for the next time we need it
    configcache[plugin_config] = {
      category_names = category_names,
      category_checks = category_checks,
    }
    return rawget(configcache, plugin_config)
  end,
})



-- Validate the response from Azure Cognitive Services. Check if the
-- categories we defined have been breached.
-- @tparam string cog_response the response body as received from Azure
-- @tparam table conf the plugin configuration
-- @treturn[1] boolean valid or not
-- @treturn[1] string reason for failure
-- @treturn[2] nil
-- @treturn[2] nil
-- @treturn[2] string error message
local function check_cog_serv_response(cog_response, conf)
  local result, err = cjson.decode(cog_response)
  if err then
    return false, "", "content safety introspection failure"
  end

  if (type(result.categoriesAnalysis) ~= "table") or (#result.categoriesAnalysis == 0) then
    return false, "", "content safety introspection is invalid"
  end

  local buf = buffer.new()
  local ok = true
  for _, v in ipairs(result.categoriesAnalysis) do
    local category_name = v.category
    local failure_level = configcache[conf].category_checks[v.category]

    if failure_level and (v.severity >= failure_level) then
      -- store in AI analytics
      kong.log.set_serialize_value(
        "ai.audit.azure_content_safety." .. category_name,
        failure_level)

      -- hack to prevent adding '; ' to the end of a single-cat failure
      if not ok then
        buf:put("; ")
      end

      ok = false
      buf:put("breached category [" .. category_name .. "] at level " .. failure_level)
    end  -- else just ignore it, we didn't define a failure threshold
  end

  return ok, buf:tostring(), nil
end



-- Builds and executes the request to Azure Cognitive Services.
-- @tparam string text the request body as received from the client, must contain JSON
-- @treturn[1] string response body as received from Azure
-- @treturn[2] nil
-- @treturn[2] string error message
local function cog_serv_request(text, conf)
  local body, err = cjson.decode(text)
  if err or type(body) ~= "table" then
    return bad_request("request is not in json format")
  end

  if (type(body.messages) ~= "table") or (#body.messages == 0) then
    return bad_request("request [messages] array is empty or missing")
  end

  local buf = buffer.new()
  if conf.text_source == "concatenate_all_content" then
    for i, v in ipairs(body.messages) do
      buf:put((v.content or " ") .. "\n\n")
    end

  elseif conf.text_source == "concatenate_user_content" then
    for _, v in ipairs(body.messages) do
      if v.role == "user" then
        buf:put((v.content or " ") .. "\n\n")
      end
    end

  else
    error("unknown text_source: " .. tostring(conf.text_source))
  end

  local request_body = {
    text = buf:tostring(),
    categories = configcache[conf].category_names,
    blocklistNames = conf.blocklist_names,
    haltOnBlocklistHit = conf.halt_on_blocklist_hit,
    outputType = conf.output_type,
  }

  local err
  kong.log.inspect("inspecting with azure content safety: ", request_body)
  request_body, err = cjson.encode(request_body)
  if not request_body then
    return nil, "failed to encode request: " .. err
  end

  -- different auth mechanisms have different headers
  local headers = {
    ["Content-Type"] = "application/json",
    ["Accept"] = "application/json",
  }
  if conf.azure_use_managed_identity then
    local client = clientcache[conf]
    local _, token, _, err = client.credentials:get()

    if err then
      kong.log.err("failed to authenticate with Azure Content Services, ", err)
      return kong.response.exit(500, { error = { message = "failed to authenticate with Azure Content Services" }})
    end

    headers["Authorization"] = "Bearer " .. token
  else
    headers["Ocp-Apim-Subscription-Key"] = conf.content_safety_key
  end

  local httpc = http.new()

  -- Single-shot requests use the `request_uri` interface.
  local res, err = httpc:request_uri(conf.content_safety_url, {
    method = "POST",
    body = request_body,
    query = "?api-version=" .. conf.azure_api_version,
    headers = headers,
  })
  if not res then
    return nil, "request failed: " .. err
  end

  if res.status ~= 200 then
    return nil, "bad content safety status: " ..
      res.status ..
      ", response: "
      .. (res.body or "EMPTY_RESPONSE")
  end

  return res.body
end



-- Main entry point for the plugin. This function will be called
-- for every request that is processed by Kong.
function plugin:access(conf)
  local response, err = cog_serv_request(kong.request.get_raw_body(), conf)
  if not response then
    kong.log.err(err)
    return kong.response.exit(500)
  end

  local valid, reason, err = check_cog_serv_response(response, conf)
  if err then
    kong.log.err(err)
    return kong.response.exit(500)
  end

  if not valid then
    if conf.reveal_failure_reason then
      return bad_request("request failed content safety check: " .. reason)
    else
      return bad_request("request failed content safety check")
    end

  end

  -- request passes, continue
end



-- export functions only when we're testing
if _G.TEST then
  plugin._check_cog_serv_response = check_cog_serv_response
end



return plugin
