-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local sha256_hex = require "kong.tools.sha256".sha256_hex
local vectordb = require("kong.llm.vectordb")
local embeddings = require("kong.llm.embeddings")

local guards_by_plugin_key = {}
local BYPASS_CACHE = true

local function delete_guard_instance(conf)
  local conf_key = conf.__plugin_id
  assert(conf_key, "missing plugin conf key __plugin_id")

  local guard = guards_by_plugin_key[conf_key]
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

  guards_by_plugin_key[conf_key] = nil
end

local function get_guard_instance(conf, bypass_cache)
  local conf_key = conf.__plugin_id
  assert(conf_key, "missing plugin conf key __plugin_id")

  local guard = guards_by_plugin_key[conf_key]
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
      guards_by_plugin_key[conf_key] = nil
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

    guards_by_plugin_key[conf_key] = guard
  end

  return guard
end

local function cleanup_by_configs(configs)
  local current_config_ids = {}

  for _, conf in ipairs(configs or {}) do
    local k = conf.__plugin_id
    if guards_by_plugin_key[k] then
      kong.log.warn("plugin instance is recreated: ", k, ", all previous guard state is reset")
    end
    assert(get_guard_instance(conf, BYPASS_CACHE))
    current_config_ids[k] = true
  end

  -- purge non existent guards
  local keys_to_delete = {}
  for k, _ in pairs(guards_by_plugin_key) do
    if not current_config_ids[k] then
      keys_to_delete[k] = true
    end
  end
  for _, k in ipairs(keys_to_delete) do
    delete_guard_instance(k)
    kong.log.debug("plugin instance is delete: ", k)
  end
end

return {
  get_guard_instance = get_guard_instance,
  delete_guard_instance = delete_guard_instance,
  cleanup_by_configs = cleanup_by_configs,
}