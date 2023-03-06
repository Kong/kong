local typedefs = require "kong.db.schema.typedefs"

---@class kong.db.schema.entities.wasm_filter_chain : table
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
    { name    = { type = "string", required = true, }, },
    { config  = { type = "string", required = false, }, },
    { enabled = { type = "boolean", default = true, required = true, }, },
  },
}


return {
  name = "wasm_filter_chains",
  primary_key = { "id" },
  endpoint_key = "name",
  admin_api_name = "wasm/filter-chains",
  generate_admin_api = true,
  workspaceable = true,
  dao = "kong.db.dao.wasm_filter_chains",

  fields = {
    { id         = typedefs.uuid },
    { name       = typedefs.utf8_name { required = false, unique = true }, },
    { enabled    = { type = "boolean", required = true, default = true, }, },
    { route      = { type = "foreign", reference = "routes",   default = ngx.null, on_delete = "cascade", }, },
    { service    = { type = "foreign", reference = "services", default = ngx.null, on_delete = "cascade", }, },
    { protocols  = typedefs.protocols },
    { filters    = { type = "array", required = true, elements = filter, len_min = 1, } },
    { created_at = typedefs.auto_timestamp_s },
    { updated_at = typedefs.auto_timestamp_s },
    { tags       = typedefs.tags },
  },
}
