-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints = require "kong.api.endpoints"
local utils = require "kong.tools.utils"
local cjson = require "cjson"
local consumer_group_helpers = require "kong.enterprise_edition.consumer_groups_helpers"
local kong = kong
local table = table
local ngx = ngx
local null = ngx.null
local fmt = string.format
local escape_uri = ngx.escape_uri
local consumer_schema = kong.db.consumers.schema
local consumer_groups_schema = kong.db.consumer_groups.schema
local consumer_group_rla_plugins_schema = kong.db.consumer_group_plugins.schema

local function get_entity(self, db, schema, handle_error)
  local entity, _, err_t = endpoints.select_entity(self, db, schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end
  if not entity then
    handle_error()
  end
  return entity
end

local function set_consumer_groups(self, db)
  self.consumer_group = get_entity(self, db, consumer_groups_schema, function()
    return kong.response.error(404, "Group '" .. self.params.consumer_groups .. "' not found")
  end)
end

local function set_consumers(self, db)
  self.consumer = get_entity(self, db, consumer_schema, function()
    return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found")
  end)
end

local function query_by_page(url, callback, page_handler, ...)
  local next_url = {}
  local next_page = nil
  local data, _, err_t, offset = page_handler(...)
  if err_t then
    return endpoints.handle_error(err_t)
  end

  if offset then
    table.insert(next_url, fmt("offset=%s", escape_uri(offset)))
  end

  if next(next_url) then
    next_page = url .. "?" .. table.concat(next_url, "&")
  end
  return kong.response.exit(200, {
    data   = setmetatable(callback(data), cjson.empty_array_mt),
    offset = offset,
    next   = next_page or null
  })
end

return {
  ["/consumer_groups"] = {
    schema = consumer_groups_schema,
    methods = {
      GET = function(self, db, _, parent)
        local args = self.args.uri
        if not args.counter then
          return parent()
        end

        return query_by_page("/consumer_groups",
          function(data)
            for _, group in pairs(data) do
              group["consumers_count"] = kong.db.consumer_group_consumers:count_consumers_in_group(group.id)
            end

            return data
          end,
          function(...)
            return endpoints.page_collection(...)
          end,
          self,
          db,
          consumer_groups_schema
        )
      end
    }
  },
  ["/consumer_groups/:consumer_groups"] = {
    schema = consumer_groups_schema,
    methods = {
      GET = function(self, db)
        set_consumer_groups(self, db)
        --get plugins and consumers
        local consumers = consumer_group_helpers.get_consumers_in_group(self.consumer_group.id)
        local plugins = consumer_group_helpers.get_plugins_in_group(self.consumer_group.id)
        return kong.response.exit(200,
          {
            consumer_group = self.consumer_group,
            plugins = plugins,
            consumers = consumers,
          }
        )
      end,

      PUT = function(self, db, helpers)
        return endpoints.put_entity_endpoint(consumer_groups_schema)(self, db, helpers)
      end,
    },
  },

  ["/consumer_groups/:consumer_groups/consumers"] = {
    schema = consumer_schema,
    methods = {
      before = function(self, db)
        set_consumer_groups(self, db)
      end,

      GET = function(self)
        local args = self.args.uri
        return query_by_page(fmt("/consumer_groups/%s/consumers", self.consumer_group.id),
          function(data)
            local consumers = {}
            local index = 0
            for _, group in pairs(data) do
              index = index + 1
              consumers[index] = kong.db.consumers:select(group.consumer)
            end
            return consumers
          end,
          function(...)
            return kong.db.consumer_group_consumers:page_for_consumer_group(...)
          end,
          { id = self.consumer_group.id },
          endpoints.get_page_size(args),
          args.offset,
          endpoints.extract_options(args, consumer_schema, "page")
        )
      end,

      POST = function(self)
        local consumer = self.args.post.consumer
        if not consumer then
          return kong.response.error(400, "must provide consumer")
        end
        
        local request_consumers = {}
        if type(consumer) == "string" then
          table.insert(request_consumers, consumer)
        else
          request_consumers = consumer
        end
        
        --filter the list before processing
        local consumers = {}
        for _, request_consumer in pairs(request_consumers) do
          local consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, request_consumer)
          if not consumer then
            return kong.response.error(404, "Consumer '" .. request_consumer .. "' not found")
          end
          if consumer_group_helpers.is_consumer_in_group(consumer.id, self.consumer_group.id) then
            return kong.response.error(409,
              "Consumer '" .. request_consumer ..
              "' already in group '" .. self.consumer_group.id .. "'")
          end
          table.insert(consumers, consumer)
        end

        for _, consumer in ipairs(consumers) do
          local _, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = self.consumer_group.id },
              consumer = { id = consumer.id },
            }
          )
          if err_t then
            return endpoints.handle_error(err_t)
          end
          local cache_key_scan = kong.db.consumer_group_consumers:cache_key("", consumer.id)
          kong.cache:invalidate(cache_key_scan)
          local cache_key = kong.db.consumer_group_consumers:cache_key(self.consumer_group.id, consumer.id)
          kong.cache:invalidate(cache_key)
        end

        return kong.response.exit(201, {
          consumer_group = self.consumer_group,
          consumers = consumers,
        })
      end,

      DELETE = function(self)
        local consumers = consumer_group_helpers.get_consumers_in_group(self.consumer_group.id)
        if not consumers then
          return kong.response.error(404, "Group '" .. self.consumer_group.id .. "' has no consumers")
        end
        for i = 1, #consumers do
          consumer_group_helpers.delete_consumer_in_group(consumers[i].id, self.consumer_group.id)
        end
        return kong.response.exit(204)
      end,
    },
  },

  ["/consumer_groups/:consumer_groups/consumers/:consumers"] = {
    schema = consumer_schema,
    methods = {
      before = function(self, db)
        set_consumers(self, db)
        set_consumer_groups(self, db)

        local params = self.params
        local is_consumer_in_group = consumer_group_helpers.is_consumer_in_group(
          self.consumer.id,
          self.consumer_group.id)
        
        if not is_consumer_in_group then
          return kong.response.error(404,
            "Consumer '" .. params.consumers .. "' not found in Group '" .. params.consumer_groups .. "'")
        end
        
      end,

      GET = function(self)
        return kong.response.exit(200, {
          consumer = self.consumer
        })
      end,

      DELETE = function(self)
        consumer_group_helpers.delete_consumer_in_group(self.consumer.id, self.consumer_group.id)
        return kong.response.exit(204)
      end,
    },
  },

  ["/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced"] = {
    schema = consumer_group_rla_plugins_schema,
    methods = {
      before = function(self, db)
        set_consumer_groups(self, db)
        self.params.plugins = "rate-limiting-advanced"
      end,

      PUT = function(self)
        local config = self.args.post.config
        if not config then
          return kong.response.error(400, "No configuration provided")
        end

        local cache_key = kong.db.consumer_group_plugins:cache_key(self.consumer_group.id, self.params.plugins)
        local record = kong.db.consumer_group_plugins:select_by_cache_key(cache_key)
        local id = record and record.id or utils.uuid()
        local _, _, err_t = kong.db.consumer_group_plugins:upsert(
          { id = id, },
          {
            name = self.params.plugins,
            consumer_group = { id = self.consumer_group.id, },
            config = config,
          }
        )
        if err_t then
          return endpoints.handle_error(err_t)
        end

        return kong.response.exit(201, {
          consumer_group = self.consumer_group.name,
          plugin = self.params.plugins,
          config = config
        })
      end,

      DELETE = function(self)
        local cache_key = kong.db.consumer_group_plugins:cache_key(self.consumer_group.id, self.params.plugins)
        local record = kong.db.consumer_group_plugins:select_by_cache_key(cache_key)
        if not record then
          return kong.response.error(404, "Consumer group config for id '" .. self.consumer_group.id .. "' not found")
        end

        local consumer_group_config_id = record.id
        local _, _, err_t = kong.db.consumer_group_plugins:delete { id = consumer_group_config_id }
        if err_t then
          return endpoints.handle_error(err_t)
        end

        return kong.response.exit(204)
      end,
    },
  },

  ["/consumers/:consumers/consumer_groups"] = {
    schema = consumer_groups_schema,
    methods = {
      before = function(self, db)
        set_consumers(self, db)
      end,

      POST = function(self)
        local group = self.args.post.group
        if not group then
          return kong.response.error(400, "must provide group")
        end
        local consumer_groups = {}
        local request_consumer_groups = {}
        if type(group) == "string" then
          table.insert(request_consumer_groups, group)
        else
          request_consumer_groups = group
        end
        --validate the list before processing
        for _, request_group in ipairs(request_consumer_groups) do
          local consumer_group = consumer_group_helpers.get_consumer_group(request_group)
          if not consumer_group then
            return kong.response.error(404, "Group '" .. request_group .. "' not found")
          end
          if consumer_group_helpers.is_consumer_in_group(self.consumer.id, consumer_group.id) then
            return kong.response.error(409,
              "Consumer '" .. self.params.consumers ..
              "' already in group '" .. request_group .. "'")
          end
          table.insert(consumer_groups, consumer_group)
        end

        for _, consumer_group in ipairs(consumer_groups) do
          local _, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = consumer_group.id },
              consumer = { id = self.consumer.id },
            }
          )
          if err_t then
            return endpoints.handle_error(err_t)
          end
        end

        return kong.response.exit(201, {
          consumer_groups = consumer_groups,
          consumer = self.consumer,
        })
      end,

      GET = function(self)
        local args = self.args.uri
        return query_by_page("/consumers/" .. self.consumer.id .. "/consumer_groups",
          function(data)
            local groups = {}
            local index = 0
            for _, group in pairs(data) do
              index = index + 1
              local consumer_group = consumer_group_helpers.get_consumer_group(group.consumer_group.id)
              consumer_group["consumers_count"] = kong.db.consumer_group_consumers:count_consumers_in_group(group.consumer_group.id)
              groups[index] = consumer_group
            end
            
            return groups
          end,
          function(...)
            return kong.db.consumer_group_consumers:page_for_consumer(...)
          end,
          { id = self.consumer.id },
          endpoints.get_page_size(args),
          args.offset,
          endpoints.extract_options(args, consumer_groups_schema, "page")
        )
      end,

      DELETE = function(self)
        local consumer_groups = consumer_group_helpers.get_groups_by_consumer(self.consumer.id)
        if not consumer_groups then
          return kong.response.error(404, "Consumer '" .. self.consumer.id .. "' not in group")
        end
        for i = 1, #consumer_groups do
          consumer_group_helpers.delete_consumer_in_group(self.consumer.id, consumer_groups[i].id)
        end
        return kong.response.exit(204)
      end,
    }
  },

  ["/consumers/:consumers/consumer_groups/:consumer_groups"] = {
    schema = consumer_groups_schema,
    methods = {
      before = function(self, db)
        set_consumers(self, db)
        set_consumer_groups(self, db)

        local params = self.params
        local is_consumer_in_group = consumer_group_helpers.is_consumer_in_group(
          self.consumer.id,
          self.consumer_group.id)

        if not is_consumer_in_group then
          return kong.response.error(404,
            "Consumer '" .. params.consumers .. "' not found in Group '" .. params.consumer_groups .. "'")
        end
        
      end,

      GET = function(self)
        return kong.response.exit(200, {
          consumer_group = self.consumer_group,
        })
      end,

      DELETE = function(self)
        consumer_group_helpers.delete_consumer_in_group(self.consumer.id, self.consumer_group.id)
        return kong.response.exit(204)
      end,
    },
  }
}
