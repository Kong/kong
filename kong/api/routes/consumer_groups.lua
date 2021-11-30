-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local endpoints          = require "kong.api.endpoints"
local utils              = require "kong.tools.utils"
local consumer_group_helpers        = require "kong.enterprise_edition.consumer_groups_helpers"
local kong = kong
local table = table

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
  ["/consumer_groups/:consumer_groups"] = {
    GET = function(self, db, helpers)
    local err
    self.consumer_group, err = get_group_from_endpoint(self, db)
    if err then
      return err
    end
    --get plugins and consumers
    local consumers = consumer_group_helpers.get_consumers_in_group(self.consumer_group.id)
    local plugins = consumer_group_helpers.get_plugins_in_group(self.consumer_group.id)

    return kong.response.exit(200, {
                                    consumer_group = self.consumer_group,
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
      if not self.params.consumer then
        return kong.response.error(400, "must provide consumer")
      end
      local consumers = {}
      --handle 1 or more consumers
      if type(self.params.consumer) == "string" then
        table.insert(consumers, self.params.consumer)
        self.params.consumer = consumers
      end
        --filter the list before processing
      for i = 1, #self.params.consumer do
        self.consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, self.params.consumer[i])
        if not self.consumer then
          return kong.response.error(404, "Consumer '" .. self.params.consumer[i] .. "' not found")
        end
        if consumer_group_helpers.is_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.error(409,
            "Consumer '" .. self.params.consumer[i] ..
            "' already in group '" .. self.consumer_group.id .."'")
        end
      end

      consumers = {}
      for i = 1, #self.params.consumer do
        self.consumer = consumer_group_helpers.select_by_username_or_id(kong.db.consumers, self.params.consumer[i])
        local _, _, err_t = kong.db.consumer_group_consumers:insert(
          {
            consumer_group = { id = self.consumer_group.id },
            consumer = { id = self.consumer.id},
          }
        )
        if err_t then
          return endpoints.handle_error(err_t)
        end
        table.insert(consumers, self.consumer)
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

  ["/consumer_groups/:consumer_groups/consumers/:consumers"] = {
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

  ["/consumer_groups/:consumer_groups/overrides/plugins/rate-limiting-advanced"] ={
    PUT = function(self, db, helpers)
      local err
      self.consumer_group, err = get_group_from_endpoint(self, db)
      if err then
        return err
      end

      if not self.params.config then
        return kong.response.error(400, "No configuration provided")
      end

      self.params.plugins = "rate-limiting-advanced"
      local record = kong.db.consumer_group_plugins:select_by_name(self.params.plugins)
      local id
      if not record then
        id = utils.uuid()
      end
      if record then
        id = record.id
      end
      local _, _, err_t = kong.db.consumer_group_plugins:upsert(
              { id = id, },
              {
                name = self.params.plugins,
                consumer_group = { id = self.consumer_group.id, },
                config = self.params.config,
              }
      )
      if err_t then
        return endpoints.handle_error(err_t)
      end
      return kong.response.exit(201, {
        group = self.consumer_group.name,
        plugin = self.params.plugins,
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
      self.consumer = consumer_in_path
    end,

    POST = function(self, db, helpers)
      if not self.params.group then
        return kong.response.error(400, "must provide group")
      end

      local consumer_groups = {}
      if type(self.params.group) == "string" then
        table.insert(consumer_groups, self.params.group)
        self.params.group = consumer_groups
      end
        --validate the list before processing
      for i = 1, #self.params.group do
        self.consumer_group = consumer_group_helpers.get_consumer_group(self.params.group[i])
        if not self.consumer_group then
          return kong.response.error(404, "Group '" .. self.params.group[i] .. "' not found")
        end
        if consumer_group_helpers.is_consumer_in_group(self.consumer.id, self.consumer_group.id) then
          return kong.response.error(409,
            "Consumer '" .. self.params.consumers ..
            "' already in group '" .. self.params.group[i] .."'")
        end
      end

      consumer_groups = {}
      for i = 1, #self.params.group do
        self.consumer_group = consumer_group_helpers.get_consumer_group(self.params.group[i])
        local _, _, err_t = kong.db.consumer_group_consumers:insert(
          {
              consumer_group = { id = self.consumer_group.id },
              consumer = { id = self.consumer.id },
          }
        )
        if err_t then
          return endpoints.handle_error(err_t)
        end
        table.insert(consumer_groups, self.consumer_group)
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

  }
}