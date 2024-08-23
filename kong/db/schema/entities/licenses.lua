-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local license_helpers = require "kong.enterprise_edition.license_helpers"

local sha256_hex = require("kong.tools.sha256").sha256_hex

return {
  name = "licenses",
  primary_key = { "id" },
  workspaceable = false,
  db_export = true,   -- maybe play with this if we don't want it passed along?
  fields = {
    { id             = typedefs.uuid },
    { payload        = { description = "The license payload.", 
                         type = "string",
                         required = true,
                         unique = true,
                         custom_validator = license_helpers.is_valid_license,
                         encrypted = true,
                       }
    },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
    { checksum       = { type = "string",
                         description = "The computed checksum of the license payload.",
                         unique = true,
                         immutable = true,
                       },
    },
  },
  transformations = {
    {
      input = { "payload" },
      on_write = function(payload)
        local result = {}

        if type(payload) == "string" then
          result.checksum = sha256_hex(payload)
        end

        return result
      end,
    },
  },
}
