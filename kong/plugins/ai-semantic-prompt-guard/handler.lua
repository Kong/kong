-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local buffer = require("string.buffer")
local embeddings     = require("kong.ai.embeddings")
local vectordb = require("kong.llm.vectordb")
local sha256_hex     = require("kong.tools.sha256").sha256_hex

local plugin = {
  PRIORITY = 775,
  VERSION = require("kong.meta").core_version
}

local guard_by_plugin_key = {}
local BYPASS_CACHE = true

local function delete_guard_instance(conf)
  local conf_key = conf.__plugin_id
  assert(conf_key, "missing plugin conf key __plugin_id")

  local guard = guard_by_plugin_key[conf_key]
  if not guard then
    return
  end

  local namespace = "ai-semantic-prompt-guard:" .. conf_key
  local allow_namespace = namespace .. ":allow"
  local deny_namespace = namespace .. ":deny"
  local allow_semanticdb, err = vectordb.new(conf.vectordb.strategy, allow_namespace, conf.vectordb)
  if err then
    kong.log.err("unable to create vectordb:" .. err)
    return
  end
  if not allow_semanticdb then
    kong.log.err("unable to create vectordb")
    return
  end

  local deny_semanticdb, err = vectordb.new(conf.vectordb.strategy, deny_namespace, conf.vectordb)
  if err then
    kong.log.err("unable to create vectordb:" .. err)
    return
  end
  if not deny_semanticdb then
    kong.log.err("unable to create vectordb")
    return
  end

  local ok, err = allow_semanticdb:drop_index(true)
  if not ok then
    kong.log.err("unable to drop index for allow prompts: " .. (err or "nil"))
  end

  local ok, err = deny_semanticdb:drop_index(true)
  if not ok then
    kong.log.err("unable to drop index for deny prompts: " .. (err or "nil"))
  end

  guard_by_plugin_key[conf_key] = nil
end

local function get_guard_instance(conf, bypass_cache)
  local conf_key = conf.__plugin_id
  assert(conf_key, "missing plugin conf key __plugin_id")

  local guard = guard_by_plugin_key[conf_key]
  if not guard or bypass_cache then
    local embedding, err = embeddings.new(conf.embeddings, conf.vectordb.dimensions)
    if err then
      return nil, "unable to create embeddings: " .. err
    end

    local namespace = "ai-semantic-prompt-guard:" .. conf_key
    local allow_namespace = namespace .. ":allow"
    local deny_namespace = namespace .. ":deny"
    local allow_semanticdb, err = vectordb.new(conf.vectordb.strategy, allow_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not allow_semanticdb then
      return nil, "unable to create vectordb"
    end

    local deny_semanticdb, err = vectordb.new(conf.vectordb.strategy, deny_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not deny_semanticdb then
      return nil, "unable to create vectordb"
    end


    if bypass_cache and guard then
      guard_by_plugin_key[conf_key] = nil
      local _, err = allow_semanticdb:drop_index(true)
      if err then
        kong.log.info("unable to delete cache for allow_prompt: ", err)
      end
    
      local _, err = deny_semanticdb:drop_index(true)
      if err then
        kong.log.info("unable to delete cache for deny_prompt: ", err)
      end
    end

    guard = {
      embeddings = embedding,
    }

    for i, prompt in ipairs(conf.rules.allow_prompts or {}) do
      local embedding, _, err = guard.embeddings:generate(prompt)
      if not embedding then
        return nil, "unable to generate embeddings for prompt: " .. err
      end
      local payload = {action="allow", prompt=prompt}
      local keyid = sha256_hex(prompt)
      local _, err = allow_semanticdb:insert(embedding, payload, keyid)
      if err then
        return nil, "unable to set cache for prompt: " .. err
      end
    end

    for _, prompt in ipairs(conf.rules.deny_prompts or {}) do
      local embedding, _, err = guard.embeddings:generate(prompt)
      if not embedding then
        return nil, "unable to generate embeddings for prompt: " .. err
      end
      local payload = {action="deny", prompt=prompt}
      local keyid = sha256_hex(prompt)
      local _, err = deny_semanticdb:insert(embedding, payload, keyid)
      if err then
        return nil, "unable to set cache for prompt: " .. err
      end
    end

    guard_by_plugin_key[conf_key] = guard
  end

  return guard
end


local function bad_request(msg)
  kong.log.debug(msg)
  return kong.response.exit(400, { error = { message = msg } })
end



local execute do
  local bad_format_error = "ai-semantic-prompt-guard only supports llm/v1/chat or llm/v1/completions prompts"

  -- Checks the prompt for the given patterns.
  -- _Note_: if a regex fails, it returns a 500, and exits the request.
  -- @tparam table request The deserialized JSON body of the request
  -- @tparam table conf The plugin configuration
  -- @treturn[1] table The decorated request (same table, content updated)
  -- @treturn[2] nil
  -- @treturn[2] string The error message
  function execute(request, conf)
    local collected_prompts
    local messages = request.messages

    -- concat all prompts into one string, if conversation history must be checked
    if type(messages) == "table" then
      local buf = buffer.new()

      -- iterate in reverse so we get the latest user prompt first
      -- instead of the oldest one in history
      for i=#messages, 1, -1 do
        local v = messages[i]
        if type(v.role) ~= "string" then
          return nil, bad_format_error
        end
        if v.role == "user" or conf.rules.match_all_roles then
          if type(v.content) ~= "string" then
            return nil, bad_format_error
          end
          buf:put(v.content)

          if not conf.rules.match_all_conversation_history then
            break
          end

          buf:put(" ") -- put a seperator to avoid adhension of words
        end
      end

      collected_prompts = buf:get()

    elseif type(request.prompt) == "string" then
      collected_prompts = request.prompt

    else
      return nil, bad_format_error
    end

    if not collected_prompts then
      return nil, "no 'prompt' or 'messages' received"
    end

    local guard, err = get_guard_instance(conf, false)
    if err or not guard then
      return nil, "unable to get guard instance: " .. (err or "nil")
    end

    local embedding, err = guard.embeddings:generate(collected_prompts)
    if not embedding then
      return nil, "unable to generate embeddings for request: " .. (err or "nil")
    end


    local namespace = "ai-semantic-prompt-guard:" .. conf.__plugin_id
    local allow_namespace = namespace .. ":allow"
    local deny_namespace = namespace .. ":deny"
    local allow_semanticdb, err = vectordb.new(conf.vectordb.strategy, allow_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not allow_semanticdb then
      return nil, "unable to create vectordb"
    end

    local deny_semanticdb, err = vectordb.new(conf.vectordb.strategy, deny_namespace, conf.vectordb)
    if err then
      return nil, "unable to create vectordb:" .. err
    end
    if not deny_semanticdb then
      return nil, "unable to create vectordb"
    end

    local out = {}
    local res
    if #(conf.rules.deny_prompts or {}) > 0 then
      res = deny_semanticdb:search(embedding, conf.vectordb.threshold, out)
    end

    if res == nil then
      res = allow_semanticdb:search(embedding, conf.vectordb.threshold, out)
    end

    if res == nil then
      if #(conf.rules.allow_prompts or {}) == 0 then
        -- no allow_patterns, so we're good
        return true
      else
        return false, "prompt doesn't match any allowed pattern"
      end
    end

    local cjson = require("cjson")
    ngx.log(ngx.ERR, "prompt matched: ", cjson.encode(out))
    ngx.log(ngx.ERR, "prompt payload: ", cjson.encode(res))
    if res.action == "deny" then
      return false, "prompt pattern is blocked"
    end

    if res.action == "allow" then
      return true
    end

    -- should not reach here
    return false, "unexcepted action in matched rule"
  end
end



function plugin:access(conf)
  kong.service.request.enable_buffering()

  -- if plugin ordering was altered, receive the "decorated" request
  local request, err = kong.request.get_body("application/json", nil, conf.rules.max_request_body_size)
  if err then
    return bad_request(err)
  elseif type(request) ~= "table" then
    return bad_request("this LLM route only supports application/json requests")
  end

  -- run access handler
  local ok, err = execute(request, conf)
  if not ok then
    kong.log.err(err)
    return bad_request("bad request") -- don't let users know 'ai-prompt-guard' is in use
  end
end

-- crud event handler for traditional mode
function plugin:init_worker()
  -- we need to consider the case of dbless mode. Currently, dbless mode does not have crud events,
  -- so we do not know how to flush the existing dirty data index
  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  local worker_events = kong.worker_events
  local cluster_events = kong.configuration.role == "traditional" and kong.cluster_events

  worker_events.register(function(data)
    local conf = data.entity.config

    local operation = data.operation
    if operation == "create" or operation == "update" then
      conf.__plugin_id = assert(data.entity.id, "missing plugin conf key __plugin_id")
      get_guard_instance(conf, BYPASS_CACHE)

    elseif operation == "delete" then
      local conf_key = data.entity.id
      conf.__plugin_id = assert(data.entity.id, "missing plugin conf key __plugin_id")
      assert(conf_key, "missing plugin conf key data.entity.id")
      delete_guard_instance(conf)
    end
  end, "ai-semantic-prompt-guard", "flush")

  -- event handlers to update balancer instances
  worker_events.register(function(data)
    if data.entity.name == "ai-semantic-prompt-guard" then
      -- broadcast this to all workers becasue dao events are sent using post_local
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }
      worker_events.post("ai-semantic-prompt-guard", "flush", post_data)

      if cluster_events then
        cluster_events:broadcast("ai-semantic-prompt-guard:flush", post_data)
      end
    end
  end, "crud", "plugins")

  if cluster_events then
    cluster_events:subscribe("ai-semantic-prompt-guard:flush", function(data)
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }
      worker_events.post("ai-semantic-prompt-guard", "flush", post_data)
    end)
  end
end


-- crud event handler for hybrid mode
function plugin:configure(configs)
  if not configs then
    return
  end

  local current_config_ids = {}

  for _, conf in ipairs(configs) do
    local k = conf.__plugin_id
    get_guard_instance(conf, BYPASS_CACHE)
    current_config_ids[k] = true
  end

  -- purge non existent balancers
  local keys_to_delete = {}
  for k, _ in pairs(guard_by_plugin_key) do
    if not current_config_ids[k] then
      keys_to_delete[k] = true
    end
  end
  for _, k in ipairs(keys_to_delete) do
    guard_by_plugin_key[k] = nil
    kong.log.debug("plugin instance is delete: ", k)
  end
end


return plugin
