-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.plugins.jq.typedefs"
local common_typedefs = require "kong.db.schema.typedefs"

return {
  name = "jq",
  fields = {
    { consumer_group = common_typedefs.no_consumer_group },
    { protocols = common_typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { request_jq_program = typedefs.jq_program },
          { request_jq_program_options = typedefs.jq_options },
          { request_if_media_type = typedefs.if_media_type },

          { response_jq_program = typedefs.jq_program },
          { response_jq_program_options = typedefs.jq_options },
          { response_if_media_type = typedefs.if_media_type },
          { response_if_status_code = typedefs.if_status_code },
        },
        entity_checks = {
          { at_least_one_of = {
            "request_jq_program",
            "response_jq_program",
          } },
        },
      },
    },
  },
}
