-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local constants = require "kong.constants"
local json_schema = require "kong.db.schema.json"
local wasm = require "kong.runloop.wasm"


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


-- FIXME: this is clunky and error-prone because a harmless refactor might
-- affect whether this file is require()-ed before or after `kong.configuration`
-- is initialized
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


return {
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
