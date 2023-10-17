local typedefs = require "kong.db.schema.typedefs"
local wasm = require "kong.runloop.wasm"
local constants = require "kong.constants"
local json_schema = require "kong.db.schema.json"


---@class kong.db.schema.entities.filter_chain : table
---
---@field id         string
---@field name       string|nil
---@field enabled    boolean
---@field route      table|nil
---@field service    table|nil
---@field created_at number
---@field updated_at number
---@field tags       string[]
---@field filters    kong.db.schema.entities.wasm_filter[]


---@class kong.db.schema.entities.wasm_filter : table
---
---@field name        string
---@field enabled     boolean
---@field config      any|nil


local filter_config_schema = {
  parent_subschema_key = "name",
  namespace = constants.SCHEMA_NAMESPACES.PROXY_WASM_FILTERS,
  optional = true,
  default = {
    ["$schema"] = json_schema.DRAFT_4,
    -- filters with no user-defined JSON schema may accept an optional
    -- config, but only as a string
    type = { "string", "null" },
  },
}


if kong and kong.configuration and kong.configuration.role == "data_plane" then
  -- data plane nodes are not guaranteed to have access to filter metadata, so
  -- they will use a JSON schema that permits all data types
  --
  -- this branch can be removed if we decide to turn off entity validation in
  -- the data plane altogether
  filter_config_schema = {
    inline = {
      ["$schema"] = json_schema.DRAFT_4,
      type = { "array", "boolean", "integer", "null", "number", "object", "string" },
    },
  }
end


local filter = {
  type = "record",
  fields = {
    { name       = { type = "string", required = true, one_of = wasm.filter_names,
                     err = "no such filter", }, },
    { enabled    = { type = "boolean", default = true, required = true, }, },

    { config = {
        type = "json",
        required = false,
        json_schema = filter_config_schema,
      },
    },

  },
}

return {
  name = "filter_chains",
  primary_key = { "id" },
  endpoint_key = "name",
  admin_api_name = "filter-chains",
  generate_admin_api = true,
  workspaceable = true,
  cache_key = { "route", "service" },

  fields = {
    { id         = typedefs.uuid },
    { name       = typedefs.utf8_name },
    { enabled    = { type = "boolean", required = true, default = true, }, },
    { route      = { type = "foreign", reference = "routes", on_delete = "cascade",
                     default = ngx.null, unique = true }, },
    { service    = { type = "foreign", reference = "services", on_delete = "cascade",
                     default = ngx.null, unique = true }, },
    { filters    = { type = "array", required = true, elements = filter, len_min = 1, } },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { tags       = typedefs.tags },
  },
  entity_checks = {
    { mutually_exclusive = {
        "service",
        "route",
      }
    },

    { at_least_one_of = {
        "service",
        "route",
      }
    },

    -- This check is for user experience and is not strictly necessary to
    -- validate filter chain input.
    --
    -- The `one_of` check on `filters[].name` already covers validation, but in
    -- the case where wasm is disabled or no filters are installed, this check
    -- adds an additional entity-level error (e.g. "wasm support is not enabled"
    -- or "no wasm filters are available").
    --
    -- All of the wasm API routes are disabled when wasm is also disabled, so
    -- this primarily serves the dbless `/config` endpoint.
    { custom_entity_check = {
        field_sources = { "filters" },
        run_with_invalid_fields = true,
        fn = wasm.status,
      },
    },
  },
}
