-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  {
    name = "header_cert_auth_credentials",
    primary_key = { "id" },
    cache_key = { "subject_name", "ca_certificate", },
    workspaceable = true,
    fields = {
      { id = typedefs.uuid },
      { created_at = typedefs.auto_timestamp_s },
      { consumer = { type = "foreign", reference = "consumers", on_delete = "cascade", }, },
      { subject_name = { type = "string", required = true, }, },
      { ca_certificate = {
        type = "foreign",
        reference = "ca_certificates",
        default = ngx.null,
        on_delete = "cascade", }, },
      { tags = typedefs.tags },
    },
  },
}

