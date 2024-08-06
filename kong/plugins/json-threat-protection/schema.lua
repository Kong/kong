-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require("kong.db.schema.typedefs")
local parse_ngx_size = require("kong.tools.string").parse_ngx_size


local concat = table.concat


local DEFAULT_UNLIMITED = -1
local DEFAULT_BODY_SIZE = 8192
-- Don't use math.huge, because in different Lua environments,
-- this may be 9223372036854775807 or -9223372036854775808
local MAX_INT = 2^31


local config = {
  name = "json-threat-protection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config   = {
        type = "record",
        fields = {
          {
            max_body_size = {
              description = "Max size of the request body. -1 means unlimited.",
              type = "integer",
              required = false,
              default = DEFAULT_BODY_SIZE,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            max_container_depth = {
              description = "Max nested depth of objects and arrays. -1 means unlimited.",
              required = false,
              type = "integer",
              default = DEFAULT_UNLIMITED,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            max_object_entry_count = {
              description = "Max number of entries in an object. -1 means unlimited.",
              required = false,
              type = "integer",
              default = DEFAULT_UNLIMITED,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            max_object_entry_name_length = {
              description = "Max string length of object name. -1 means unlimited.",
              required = false,
              type = "integer",
              default = DEFAULT_UNLIMITED,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            max_array_element_count = {
              description = "Max number of elements in an array. -1 means unlimited.",
              required = false,
              type = "integer",
              default = DEFAULT_UNLIMITED,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            max_string_value_length = {
              description = "Max string value length. -1 means unlimited.",
              required = false,
              type = "integer",
              default = DEFAULT_UNLIMITED,
              between = {DEFAULT_UNLIMITED, MAX_INT},
            },
          },
          {
            enforcement_mode = {
              description = "Enforcement mode of the security policy.",
              required = false,
              type = "string",
              one_of = { "block", "log_only" },
              default = "block",
            },
          },
          {
            error_status_code = {
              description = "The response status code when validation fails.",
              type = "integer",
              required = false,
              default = 400,
              between = {400, 499},
            },
          },
          {
            error_message = {
              description = "The response message when validation fails",
              type = "string",
              required = false,
              default = "Bad Request",
            },
          },
        },
      },
    },
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = {
          "config.max_body_size",
          "config.max_container_depth",
        },
        fn = function(entity)
          local err = {}
          for name, field in pairs(entity.config) do
            if type(field) ~= "number" or field == 0 then
               err[#err + 1] = name
            end
          end

          if #err > 0 then
            return false, concat(err, " ,") .. " shouldn't be 0."
          end

          if entity.config.max_body_size > parse_ngx_size(kong.configuration.client_body_buffer_size) then
            kong.log.warn("max_body_size exceeding client_body_buffer_size " ..
	                  "may lead to performance degradation.")
          end
          return true
        end
      },
    },
  },
}

return config
