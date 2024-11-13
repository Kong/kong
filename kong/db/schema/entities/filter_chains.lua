local typedefs = require "kong.db.schema.typedefs"
local filter = require "kong.db.schema.others.wasm_filter"
local wasm = require "kong.runloop.wasm"


---@class kong.db.schema.entities.filter_chain : table
---
---@field id         string
---@field name       string|nil
---@field enabled    boolean
---@field route      { id: string }|nil
---@field service    { id: string }|nil
---@field created_at number
---@field updated_at number
---@field tags       string[]
---@field filters    kong.db.schema.entities.wasm_filter[]


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
