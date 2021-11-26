-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints          = require "kong.api.endpoints"
local utils              = require "kong.tools.utils"
local kong = kong
local consumer_group
local consumer
local consumer_group_helpers        = require "kong.enterprise_edition.consumer_groups_helpers"
local inspect  = require "inspect"

return {
  ["/consumer_groups/:consumer_groups"] = {
    before = function(self, db, helpers)
      local group, _, err_t = endpoints.select_entity(self, db, kong.db.consumer_groups.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not group then
        if self.req.method ~= "PUT" then
        return kong.response.error(404, "Group '" .. self.params.consumer_groups .. "' not found" )
        end
      end
      consumer_group = group
    end,

    GET = function(self, db, helpers)
    --get plugins and consumers
    local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)
    local plugins = consumer_group_helpers.get_plugins_in_group(consumer_group.id)

    return kong.response.exit(200, {
                                    consumer_group = consumer_group,
                                    plugins = plugins,
                                    consumers = consumers
    })
  
    end,

    PUT = function(self, db, helpers)
      return endpoints.put_entity_endpoint(kong.db.consumer_groups.schema)
                                          (self, db, helpers)
    end,

  },

  ["/consumer_groups/:consumer_groups/consumers"] ={
    before = function(self, db, helpers)
      local group, _, err_t = endpoints.select_entity(self, db, kong.db.consumer_groups.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not group then
        if self.req.method ~= "PUT" then
        return kong.response.error(404, "Group '" .. self.params.consumer_groups .. "' not found" )
        end
      end
      consumer_group = group
    end,

    GET = function(self, db, helpers)
      consumer_group =  consumer_group_helpers.get_consumer_group(self.params.consumer_groups)
      local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)

      return kong.response.exit(201, {
        consumer_group = consumer_group,
        consumers = consumers,
      })
    end,

    POST = function(self, db, helpers)
      if not self.params.consumer then
        return kong.response.error(400, "must provide consumer")
      end

      --handle 1 or more consumers
      if type(self.params.consumer) == "string" then
        consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, self.params.consumer)
        if not consumer then
          return kong.response.error(404, "Consumer '" .. self.params.consumer .. "' not found")
        end

        local consumer_group_relation, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = consumer_group.id },
              consumer = { id = consumer.id},
            }
          )
        if not consumer_group_relation then
          return endpoints.handle_error(err_t)
        end
      else
        --filter the list before processing
        for i = 1, #self.params.consumer do
          consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, self.params.consumer[i])
          if not consumer then
            return kong.response.error(404, "Consumer '" .. self.params.consumer[i] .. "' not found")
          end
        end

        for i = 1, #self.params.consumer do
          consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, self.params.consumer[i])
          local consumer_group_relation, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = consumer_group.id },
              consumer = { id = consumer.id},
            }
          )
          if not consumer_group_relation then
            return endpoints.handle_error(err_t)
          end
        end
      end
      consumer_group =  consumer_group_helpers.get_consumer_group(self.params.consumer_groups)
      local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)

      return kong.response.exit(201, {
        consumer_group = consumer_group,
        consumers = consumers,
      })
    end,

    DELETE = function(self, db, helpers)
      local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)
      if not consumers then
        return kong.response.error(404, "Group '" .. consumer_group.id .. "' has no consumers")
      end
      for i = 1, #consumers do
        consumer_group_helpers.delete_consumer_in_group(consumers[i], consumer_group.id)
      end
      return kong.response.exit(204)
    end,
  },

  ["/consumer_groups/:consumer_groups/consumers/:consumers"] = {
    before = function(self, db, helpers)
      local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not consumer_in_path then
        return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found" )
      end
      consumer = consumer_in_path
      local group, _, err_t = endpoints.select_entity(self, db, kong.db.consumer_groups.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not group then
        return kong.response.error(404,
        { message = "Group '" .. self.params.consumer_groups .. "' not found" })
      end
      consumer_group = group
    end,

    GET = function(self, db, helpers)
      if consumer_group_helpers.is_consumer_in_group(consumer.id, consumer_group.id) then
        return kong.response.exit(200, {
          consumer = consumer
        })
      else
        return kong.response.error(404,
        "Consumer '" .. consumer.id .. "' not found in Group '" .. consumer_group.id .."'" )
      end
    end,

    DELETE = function(self, db, helpers)
      if consumer_group_helpers.delete_consumer_in_group(consumer.id, consumer_group.id) then
        return kong.response.exit(204)
      else
        return kong.response.error(404,
        "Consumer '" .. consumer.id .. "' not found in Group '" .. consumer_group.id .."'" )
      end
    end,
  },

  ["/consumer_groups/:consumer_groups/overrides/plugins/:plugins"] ={
    PUT = function(self, db, helpers)
      local group, _, err_t = endpoints.select_entity(self, db, kong.db.consumer_groups.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not group then
        return kong.response.error(404, { message = "No group named '" .. self.params.consumer_groups .. "'" })
      end

      local plugin = kong.db.plugins.schema.subschemas[self.params.plugins]
      if not plugin then
        return kong.response.exit(404, { message = "No plugin named '" .. self.params.plugins .. "'" })
      end
      if not self.params.config then
        return kong.response.error(400, "No configuration provided")
      end

      local record = kong.db.consumer_group_plugins:select_by_name(plugin.name)
      local id
      if not record then
        id = utils.uuid()
      end
      if record then
        id = record.id
      end
      local _, err_t = kong.db.consumer_group_plugins:upsert(
              { id = id, },
              {
                name = plugin.name,
                consumer_group = { id = group.id, },
                config = self.params.config,
              }
      )
      if err_t then
        return endpoints.handle_error(err_t)
      end
      return kong.response.exit(201, {
        group = group.name,
        plugin = plugin.name,
        config = self.params.config
      })
    end,

  },

  ["/consumers/:consumers/consumer_groups"] = {
    before = function(self, db, helpers)
      local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not consumer_in_path then
        return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found" )
      end
      consumer = consumer_in_path
    end,

    POST = function(self, db, helpers)
      if not self.params.group then
        return kong.response.error(400, "must provide group")
      end

      if type(self.params.group) == "string" then
        consumer_group = consumer_group_helpers.get_consumer_group(self.params.group)
        if not consumer_group then
          return kong.response.error(404, "Group '" .. self.params.group .. "' not found")
        end
        local consumer_group_relation, _, err_t = kong.db.consumer_group_consumers:insert(
          {
            consumer_group = { id = consumer_group.id },
            consumer = { id = consumer.id },
          }
        )
        if not consumer_group_relation then
          return endpoints.handle_error(err_t)
        end
      else
        --validate the list before processing
        for i = 1, #self.params.group do
          consumer_group = consumer_group_helpers.get_consumer_group(self.params.group[i])
          if not consumer_group then
            return kong.response.error(404, "Group '" .. self.params.group[i] .. "' not found")
          end
          if consumer_group_helpers.is_consumer_in_group(consumer.id, consumer_group.id) then
            return kong.response.error(409,
            "Consumer '" .. self.params.consumers ..
            "' already in group '" .. self.params.group[i] .."'")
          end
        end

        for i = 1, #self.params.group do
          consumer_group = consumer_group_helpers.get_consumer_group(self.params.group[i])
          local consumer_group_relation, _, err_t = kong.db.consumer_group_consumers:insert(
            {
              consumer_group = { id = consumer_group.id },
              consumer = { id = consumer.id },
            }
          )
          if not consumer_group_relation then
            return endpoints.handle_error(err_t)
          end
        end
      end
      return kong.response.exit(201, {
        consumer_groups = consumer_group_helpers.get_groups_by_consumer(consumer.id),
        consumer = consumer,
      })
    end,

    GET = function(self, db, helpers)
      local consumer_groups = consumer_group_helpers.get_groups_by_consumer(consumer.id)
      return kong.response.exit(200, {
        consumer_groups = consumer_groups,
      })
    end,

    DELETE = function(self, db, helpers)
      local consumer_groups = consumer_group_helpers.get_groups_by_consumer(consumer.id)
      if not consumer_groups then
        return kong.response.error(404, "Consumer '" .. consumer.id .. "' not in group")
      end
      for i = 1, #consumer_groups do
        consumer_group_helpers.delete_consumer_in_group(consumer.id, consumer_groups[i].id)
      end
      return kong.response.exit(204)
    end,
  },

  ["/consumers/:consumers/consumer_groups/:consumer_groups"] = {
    before = function(self, db, helpers)
      local consumer_in_path, _, err_t = endpoints.select_entity(self, db, db.consumers.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not consumer_in_path then
        return kong.response.error(404, "Consumer '" .. self.params.consumers .. "' not found" )
      end
      consumer = consumer_in_path
      local group = consumer_group_helpers.get_consumer_group(self.params.consuemer_groups)
      if not group then
        return kong.response.error(404, { message = "No group named '" .. self.params.consumer_groups .. "'" })
      end
      consumer_group = group
    end,

    DELETE = function(self, db, helpers)
      if consumer_group_helpers.delete_consumer_in_group(consumer.id, consumer_group.id) then
        return kong.response.exit(204)
      else
        return kong.response.error(404,
        "Consumer '" .. consumer.id .. "' not found in Group '" .. consumer_group.id .."'" )
      end
    end,

  }
}