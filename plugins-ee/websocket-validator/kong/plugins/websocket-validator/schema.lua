-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local draft4 = require "kong.tools.json-schema.draft4"


local null = ngx.null


local VALIDATION_TYPES = {
  "draft4",
}


local schema_validators = {
  draft4 = draft4.validate,
}


---@param entity kong.plugin.websocket-validator.conf.validation
---@return boolean ok
---@return string? error
local function validate_json_schema(entity)
  local typ = entity.type

  if typ == nil or typ == null then
    return true
  end

  return schema_validators[typ](entity.schema)
end


---@class kong.plugin.websocket-validator.conf.validation
---@field type    "draft4"
---@field schema  string


local content_validation = {
  type = "record",
  required = false,
  fields = {
    { type = { description = "The corresponding validation library for `config.upstream.binary.schema`. Currently, only `draft4` is supported.", type = "string",
        required = true,
        one_of = VALIDATION_TYPES,
      },
    },
    {
      schema = { description = "Schema used to validate upstream-originated binary frames. The semantics of this field depend on the validation type set by `config.upstream.binary.type`.", type = "string",
        required = true,
      },
    },
  },
  entity_checks = {
    { custom_entity_check = {
        field_sources = { "type", "schema" },
        fn = validate_json_schema,
      }
    },
  }
}


---@class kong.plugin.websocket-validator.conf.peer
---@field text    kong.plugin.websocket-validator.conf.validation
---@field binary  kong.plugin.websocket-validator.conf.validation


local peer_validation = {
  type = "record",
  required = false,
  fields = {
    { text = content_validation },
    { binary = content_validation },
  },
  entity_checks = {
    { at_least_one_of = { "text", "binary" } },
  },
}


---@class kong.plugin.websocket-validator.conf
---@field client    kong.plugin.websocket-validator.conf.peer
---@field upstream  kong.plugin.websocket-validator.conf.peer


return {
  name = "websocket-validator",
  fields = {
    { protocols = typedefs.protocols_ws },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { client = peer_validation },
          { upstream = peer_validation },
        },
        entity_checks = {
          { at_least_one_of = { "client", "upstream" } },
        },
      }
    },
  },
}