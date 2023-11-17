-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local deprecation = require "kong.deprecation"

return {
  name = "consumer_group_plugins",
  generate_admin_api = false,
  admin_api_nested_name = "plugins",
  primary_key = { "id" },
  cache_key = { "consumer_group", "name" },
  endpoint_key = "name",
  workspaceable = true,

  fields = {
    { id = typedefs.uuid },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { consumer_group = { description = "The consumer group to which the plugin is associated.", type = "foreign", required = true, reference = "consumer_groups", on_delete = "cascade" } },
    { name = { description = "The name of the plugin.", type = "string", required = true, indexed = true } },
    { config = { type = "record",
      fields = {
        { window_size = {
          description = "The window size for rate limiting.",
          type = "array",
          elements = {
            type = "number",
          },
          required = true,
        }},
        { window_type = {
          description = "The window type for rate limiting.",
          type = "string",
          one_of = { "fixed", "sliding" },
          default = "sliding",
        }},
        { limit = {
          type = "array",
          description = "The limit for rate limiting.",
          elements = {
            type = "number",
          },
          required = true,
        }},
        { retry_after_jitter_max = { -- in seconds
          description = "The maximum jitter for retry after in seconds.",
          type = "number",
          default = 0,
        }},
      }, required = true
    },
    }
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "config" },
      fn = function(entity)
        deprecation("The method of configuring plugins through this entity is now deprecated. We've introduced a more efficient way to scope plugins to Consumer Groups that follows the familiar process used with Services, Routes, and Consumers.", { after = "3.4", })
        local config = entity.config

        if not config.limit or not config.window_size then
          return true
        end

        if #config.window_size ~= #config.limit then
          return nil, "You must provide the same number of windows and limits"
        end

        -- sort the window_size and limit arrays by limit
        -- first we create a temp table, each element of which is a pair of
        -- limit/window_size values. we then sort based on the limit element
        -- of this array of pairs. finally, we re-assign the configuration
        -- elements directly based off the sorted temp table
        local t = {}
        for i, v in ipairs(config.limit) do
          t[i] = { config.limit[i], config.window_size[i] }
        end

        table.sort(t, function(a, b) return tonumber(a[1]) < tonumber(b[1]) end)

        for i = 1, #t do
          config.limit[i] = tonumber(t[i][1])
          config.window_size[i] = tonumber(t[i][2])
        end

        if config.retry_after_jitter_max < 0 then
          return nil, "Non-negative retry_after_jitter_max value is expected"
        end

        return true
      end
    }},
  },
}
