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

local function get_group_from_endpoint(self, db)
  local err
  local group, _, err_t = endpoints.select_entity(self, db, kong.db.consumer_groups.schema)
  if err_t then
    return endpoints.handle_error(err_t)
  end
  if not group then
    err = kong.response.error(404, "Group '" .. self.params.consumer_groups .. "' not found" )
  end
  return group, err
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

        local next_url = {}
        local next_page = null

        local data, _, err_t, offset = endpoints.page_collection(self, db, kong.db.consumer_groups.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end

        if offset then
          table.insert(next_url, fmt("offset=%s", escape_uri(offset)))
        end

        if next(next_url) then
          next_page = "/consumer_groups?" .. table.concat(next_url, "&")
        end

        for _, group in pairs(data) do
          group["consumers_count"] = kong.db.consumer_group_consumers:count_consumers_in_group(group.id)
        end

        setmetatable(data, cjson.empty_array_mt)

        return kong.response.exit(200, {
          data   = data,
          offset = offset,
          next   = next_page
        })
      end
    }
  },
  ["/consumer_groups/:consumer_groups"] = {
    schema = consumer_groups_schema,
    methods = {
      GET = function(self, db, helpers)
      local consumer_group, err = get_group_from_endpoint(self, db)
      if err then
        return err
      end
      --get plugins and consumers
      local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)
      local plugins = consumer_group_helpers.get_plugins_in_group(consumer_group.id)
      return kong.response.exit(200, {
                                    consumer_group = consumer_group,
                                    plugins = plugins,
                                    consumers = consumers,})

      end,

      PUT = function(self, db, helpers)
        return endpoints.put_entity_endpoint(kong.db.consumer_groups.schema)(self, db, helpers)
      end,
    },
  },

  ["/consumer_groups/:consumer_groups/consumers"] = {
    schema = consumer_schema,
    methods = {
      before = function(self, db, helpers)
        local err
        self.consumer_group, err = get_group_from_endpoint(self, db)
        if err then
          return err
        end
      end,

      GET = function(self, db, helpers)
        local consumers = consumer_group_helpers.get_consumers_in_group(self.consumer_group.id)
        return kong.response.exit(200, {
          consumers = consumers,
        })
      end,

      POST = function(self, db, helpers)
        if not self.args.post.consumer then
          return kong.response.error(400, "must provide consumer")
        end
        local consumers = {}
        local request_consumers = {}
        --handle 1 or more consumers
        if type(self.args.post.consumer) == "string" then
          table.insert(request_consumers, self.args.post.consumer)
        else
          request_consumers = self.args.post.consumer
        end

        --filter the list before processing
        for _, request_consumer in pairs(request_consumers) do
          local consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, request_consumer)
          if not consumer then
            return kong.response.error(404, "Consumer '" .. request_consumer .. "' not found")
          end
          if consumer_group_helpers.is_consumer_in_group(consumer.id, self.consumer_group.id) then
            return kong.response.error(409,
              "Consumer '" .. request_consumer ..
              "' already in group '" .. self.consumer_group.id .."'")
          end
          table.insert(consumers, consumer)
        end

        for _, consumer in ipairs(consumers) do
          local _, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = self.consumer_group.id },
              consumer = { id = consumer.id},
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

      DELETE = function(self, db, helpers)
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
      before = function(self, db, helpers)
        local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer_in_path then
          return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found")
        end
        self.consumer = consumer_in_path
        local err
        self.consumer_group, err = get_group_from_endpoint(self, db)
        if err then
          return err
        end
      end,

      GET = function(self, db, helpers)
        if consumer_group_helpers.is_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.exit(200, {
            consumer = self.consumer
          })
        end
        return kong.response.error(404,
          "Consumer '" .. self.consumer.id .. "' not found in Group '" .. self.consumer_group.id .."'" )
      end,

      DELETE = function(self, db, helpers)
        if consumer_group_helpers.delete_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.exit(204)
        end
        return kong.response.error(404,
          "Consumer '" .. self.consumer.id .. "' not found in Group '" .. self.consumer_group.id .."'" )
      end,
    },
  },

  ["/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced"] = {
    schema = consumer_group_rla_plugins_schema,
    methods = {
      PUT = function(self, db, helpers)
        local consumer_group, err = get_group_from_endpoint(self, db)
        if err then
          return err
        end
        if not self.args.post.config then
          return kong.response.error(400, "No configuration provided")
        end
        self.params.plugins = "rate-limiting-advanced"
        local cache_key = kong.db.consumer_group_plugins:cache_key(consumer_group.id, self.params.plugins)
        local record = kong.db.consumer_group_plugins:select_by_cache_key(cache_key)
        local id
        if record then
          id = record.id
        else
          id = utils.uuid()
        end
        local _, _, err_t = kong.db.consumer_group_plugins:upsert(
                { id = id, },
                {
                  name = self.params.plugins,
                  consumer_group = { id = consumer_group.id, },
                  config = self.args.post.config,
                }
        )
        if err_t then
          return endpoints.handle_error(err_t)
        end
        return kong.response.exit(201, {
          consumer_group = consumer_group.name,
          plugin = self.params.plugins,
          config = self.args.post.config
        })
      end,

      DELETE = function(self, db, helpers)
        local consumer_group, err = get_group_from_endpoint(self, db)
        if err then
          return err
        end
        if not consumer_group then
          return kong.response.error(404, "Consumer group '" .. self.params.consumer_groups.id .. "' not found")
        end
        self.params.plugins = "rate-limiting-advanced"
        local cache_key = kong.db.consumer_group_plugins:cache_key(consumer_group.id, self.params.plugins)
        local record = kong.db.consumer_group_plugins:select_by_cache_key(cache_key)
        local consumer_group_config_id
        if record then
          consumer_group_config_id = record.id
        else
          return kong.response.error(404, "Consumer group config for id '" .. consumer_group.id .. "' not found")
        end
        local _, _, err_t = kong.db.consumer_group_plugins:delete(
          { id = consumer_group_config_id, }
        )
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
      before = function(self, db, helpers)
        local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer_in_path then
          return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found" )
        end
        self.consumer = consumer_in_path
      end,

      POST = function(self, db, helpers)
        if not self.args.post.group then
          return kong.response.error(400, "must provide group")
        end
        local consumer_groups = {}
        local request_consumer_groups = {}
        if type(self.args.post.group) == "string" then
          table.insert(request_consumer_groups, self.args.post.group)
        else
          request_consumer_groups = self.args.post.group
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
              "' already in group '" .. request_group .."'")
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

      GET = function(self, db, helpers)
        local consumer_groups = consumer_group_helpers.get_groups_by_consumer(self.consumer.id)
        return kong.response.exit(200, {
          consumer_groups = consumer_groups,
        })
      end,

      DELETE = function(self, db, helpers)
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
      before = function(self, db, helpers)
        local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
        if err_t then
          return endpoints.handle_error(err_t)
        end
        if not consumer_in_path then
          return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found" )
        end
        self.consumer = consumer_in_path
        local err
        self.consumer_group, err = get_group_from_endpoint(self, db)
        if err then
          return err
        end
      end,

      GET = function(self, db, helpers)
        if consumer_group_helpers.is_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.exit(200, {
            consumer_group = self.consumer_group,
          })
        else
          return kong.response.error(404,
          "Consumer '" .. self.consumer.id .. "' not found in Group '" .. self.consumer_group.id .."'" )
        end
      end,

      DELETE = function(self, db, helpers)
        if consumer_group_helpers.delete_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.exit(204)
        else
          return kong.response.error(404,
          "Consumer '" .. self.consumer.id .. "' not found in Group '" .. self.consumer_group.id .."'" )
        end
      end,
    },
  }
}
