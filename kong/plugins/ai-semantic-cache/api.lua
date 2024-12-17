-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- imports
local require = require
local kong = kong
local vectordb = require("kong.llm.vectordb")
local HTTP_INTERNAL_SERVER_ERROR_MSG = "An unexpected error occurred"


--globals
local SEMANTIC_CACHE_NAMESPACE_PREFIX = "kong_semantic_cache:"


local function each_by_name(entity, name)
  -- it is similar with each(page_size), `nil` means default size (1000)
  local iter = entity:each()
  local function iterator()
    local element, err = iter()
    if err then return nil, err end
    if element == nil then return end
    if element.name == name then return element, nil end
    return iterator()
  end

  return iterator
end


local function get_plugin_by_id(id)
  local row, err = kong.db.plugins:select {
    id = id,
  }
  if err then
    return kong.response.exit(500, err)
  end

  if not row then
    return kong.response.exit(404)
  end

  return row
end

local function get_vectordb_for_plugin(plugin)
  local conf = plugin.config
  local namespace = SEMANTIC_CACHE_NAMESPACE_PREFIX .. plugin.id
  local vectordb_driver, err = vectordb.new(conf.vectordb.strategy, namespace, conf.vectordb)
  if err then
    return nil, err
  end

  return vectordb_driver
end

local function purge_index_and_keys(plugin)
  local vectordb_driver, err = get_vectordb_for_plugin(plugin)
  if err then
    return false, err
  end

  local ok, err = vectordb_driver:drop_index(true)
  if not ok then
    return false, err
  end

  return true
end


local function purge_key(plugin, key)
  local vectordb_driver, err = get_vectordb_for_plugin(plugin)
  if err then
    return false, err
  end

  local ok, err = vectordb_driver:delete(key)
  return ok, err
end

local function get_key(plugin, key)
  local vectordb_driver, err = get_vectordb_for_plugin(plugin)
  if err then
    return false, err
  end

  local cache_val, err = vectordb_driver:get(key)
  return cache_val, err
end


return {
  ["/ai-semantic-cache"] = {
    DELETE = function()
      for plugin, err in each_by_name(kong.db.plugins, "ai-semantic-cache") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        local _, err = purge_index_and_keys(plugin)
        if err then
          kong.response.exit(500, { message = err })
        end
      end

      return kong.response.exit(204)
    end
  },
  ["/ai-semantic-cache/:cache_key"] = {
    GET = function(self)
      for plugin, err in each_by_name(kong.db.plugins, "ai-semantic-cache") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        local cache_val, err = get_key(plugin, self.params.cache_key)

        if err then
          return kong.response.exit(500, { message = err })
        end

        if cache_val then
          return kong.response.exit(200, cache_val)
        end

        -- else continue the loop, it might not be in this redis instance
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,

    DELETE = function(self)
      for plugin, err in each_by_name(kong.db.plugins, "ai-semantic-cache") do
        if err then
          return kong.response.exit(500, { message = HTTP_INTERNAL_SERVER_ERROR_MSG })
        end

        local ok, err = purge_key(plugin, self.params.cache_key)
        if not ok then
          return kong.response.exit(500, { message = err })
        end

        if ok then
          return kong.response.exit(204)
        end
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
  },
  ["/ai-semantic-cache/:plugin_id/caches/:cache_key"] = {
    GET = function(self)
      local plugin = get_plugin_by_id(self.params.plugin_id)

      local cache_val, err = get_key(plugin, self.params.cache_key)

      if err then
        return kong.response.exit(500, { message = err })
      end

      if cache_val then
        return kong.response.exit(200, cache_val)
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
    DELETE = function(self)
      local plugin = get_plugin_by_id(self.params.plugin_id)

      local ok, err = purge_key(plugin, self.params.cache_key)
      if not ok then
        return kong.response.exit(500, { message = err })
      end

      if ok then
        return kong.response.exit(204)
      end

      -- fell through, not found
      return kong.response.exit(404)
    end,
  },
}
