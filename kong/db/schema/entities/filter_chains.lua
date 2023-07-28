local typedefs = require "kong.db.schema.typedefs"
local wasm = require "kong.runloop.wasm"


---@class kong.db.schema.entities.filter_chain : table
---
---@field id         string
---@field name       string|nil
---@field enabled    boolean
---@field route      table|nil
---@field service    table|nil
---@field protocols  table|nil
---@field created_at number
---@field updated_at number
---@field tags       string[]
---@field filters    kong.db.schema.entities.wasm_filter[]


---@class kong.db.schema.entities.wasm_filter : table
---
---@field name    string
---@field enabled boolean
---@field config  string|table|nil


local filter = {
  type = "record",
  fields = {
    { name    = { type = "string", required = true, one_of = wasm.filter_names,
                  err = "no such filter", }, },
    { config  = { type = "string", required = false, }, },
    { enabled = { type = "boolean", default = true, required = true, }, },
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
