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
local consumer_groups             = kong.db.consumer_groups
local consumer_group_helpers        = require "kong.enterprise_edition.consumer_groups_helpers"

return {
  ["/consumer_groups"] = {
    GET = function(self, db, helpers)
      return endpoints.get_collection_endpoint(consumer_groups.schema)
                                          (self, db, helpers)
    end,
  },

  ["/consumer_groups/:consumer_groups"] = {
    before = function(self, db, helpers)
      local group, _, err_t = endpoints.select_entity(self, db, db.consumer_groups.schema)
      if err_t then
        return endpoints.handle_error(err_t)
      end
      if not group then
        if self.req.method ~= "PUT" then
        return kong.response.error(404, "No group named '" .. self.params.consumer_groups .. "'" )
        end
      end
      consumer_group = group
    end,
  
    POST = function(self, db, helpers)
      if not self.params.consumer then
        return kong.response.error(400, "No consumer provided")
      end

      local consumer_id
      for i = 1, #self.params.consumer do
        if not utils.is_valid_uuid(self.params.consumer[i]) then
          local consumer, second, err_t = kong.db.consumers:select_by_username(self.params.consumer[i])
          if not consumer then
            return kong.response.error(400, "Consumer '" .. self.params.consumer[i] .. "' not found")
          end
          consumer_id = consumer.id
        else
          local consumer, _, err_t = kong.db.consumers:select(self.params.consumer[i])
          if not consumer then
            return endpoints.handle_error(err_t)
          end
          consumer_id = consumer.id
        end

      
        local consumer_group_relation, _, err_t = kong.db.consumer_group_consumers:insert(
          {
            consumer_group = { id = consumer_group.id },
            consumer = { id = consumer_id},
          }
        )
        if not consumer_group_relation then
          return endpoints.handle_error(err_t)
        end
      end
     
      local consumer_group =  consumer_group_helpers.get_consumer_group(self.params.consumer_groups)
      local consumers = consumer_group_helpers.get_consumers_in_group(consumer_group.id)
    
      return kong.response.exit(201, {
        consumer_group = consumer_group,
        consumers = consumers,
      })
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

    PUT = function (self, db, helpers)
      return endpoints.put_entity_endpoint(consumer_groups.schema)
                                          (self, db, helpers)
      
    end,


  },

  ["/consumer_groups/:consumer_groups/plugins/:plugins/overrides"] ={
    PUT = function(self, db, helpers)
      local group, _, err_t = endpoints.select_entity(self, db, db.consumer_groups.schema)
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

      local record, err_t = kong.db.consumer_group_plugins:select_by_name(plugin.name)
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

  }
}