-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local null = ngx.null


return {
  name = "plugins",
  primary_key = { "id" },
  cache_key = { "name", "route", "service", "consumer", "consumer_group" },
  dao = "kong.db.dao.plugins",
  workspaceable = true,
  endpoint_key = "instance_name",

  subschema_key = "name",
  subschema_error = "plugin '%s' not enabled; add it to the 'plugins' configuration property",

  fields = {
    { id = typedefs.uuid, },
    { name = { description = "The name of the Plugin that's going to be added.", type = "string", required = true, indexed = true }, },
    { instance_name = typedefs.utf8_name { indexed = true }  },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { route = { description = "If set, the plugin will only activate when receiving requests via the specified route.", type = "foreign", reference = "routes", default = null, on_delete = "cascade", }, },
    { service = { description = "If set, the plugin will only activate when receiving requests via one of the routes belonging to the specified service. ", type = "foreign", reference = "services", default = null, on_delete = "cascade", }, },
    { consumer = { description = "If set, the plugin will activate only for requests where the specified has been authenticated.", type = "foreign", reference = "consumers", default = null, on_delete = "cascade", }, },
    { consumer_group = { description = "If set, the plugin will activate only for requests where the specified group has been authenticated", type = "foreign", reference = "consumer_groups", on_delete = "cascade", }, },
    { config = { description = "The configuration properties for the Plugin.", type = "record", abstract = true, }, },
    { protocols = typedefs.protocols },
    { enabled = { description = "Whether the plugin is applied.", type = "boolean", required = true, default = true, indexed = true }, },
    { tags = typedefs.tags },
    { ordering = typedefs.plugin_ordering },
  },
  entity_checks = {
    {
      -- There is currently no real case that would require this combination.
      -- to keep the scope narrow, we don't allow consumer & consumer_group combinations
      -- for now.
      mutually_exclusive = {"consumer", "consumer_group"}
    },
    { custom_entity_check = {
      field_sources = { "consumer_group" },
      fn = function (entity)
        if kong and kong.licensing then
          if kong.licensing:license_type() == "free" and entity.consumer_group ~= ngx.null then
            return nil, "consumer-group scoping requires a license to be used"
          end
        end
        return true
      end
    } },
    { custom_entity_check = {
      field_sources = { "ordering" },
      fn = function (entity)
        if kong and kong.licensing then
          if kong.licensing:license_type() == "free" and entity.ordering ~= ngx.null then
            return nil, "ordering requires a license to be used"
          end
        end
        return true
      end
    } },
  }
}
