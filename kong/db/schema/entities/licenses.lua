-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

local license_helpers = require "kong.enterprise_edition.license_helpers"

return {
  name = "licenses",
  -- dao = "kong.db.dao.licenses",
  -- admin_api_name="licenses",
  -- generate_admin_api = false,
  primary_key = { "id" },
  workspaceable = false,
  db_export = true,   -- maybe play with this if we don't want it passed along?
  fields = {
    { id             = typedefs.uuid },
    { payload        = { type = "string", required = true } },
    { created_at     = typedefs.auto_timestamp_s },
    { updated_at     = typedefs.auto_timestamp_s },
  },

  entity_checks = {
    { custom_entity_check = {
      field_sources = { "payload" },
      fn = function(entity)
        -- Ensure the license is valid
        local ok, msg = license_helpers.is_valid_license(entity.payload)
        if not ok then
          ngx.log(ngx.ERR, msg)
          return nil, msg
        end

        return true
      end,
    } },
  },
}
