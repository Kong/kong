local typedefs = require "kong.plugins.jq.typedefs"

return {
  name = "jq",
  fields = {
    typedefs.protocols,
    {
      config = {
        type = "record",
        fields = {
          { request_jq_program = typedefs.program },
          { request_jq_program_options = typedefs.jq_options },
          { request_if_media_type = typedefs.if_media_type },

          { response_jq_program = typedefs.program },
          { response_jq_program_options = typedefs.jq_options },
          { response_if_media_type = typedefs.if_media_type },
          { response_if_status_code = typedefs.if_status_code },
        },
        entity_checks = {
          { at_least_one_of = {
            "request_jq_program",
            "response_jq_program"
          } },
        },
      },
    },
  },
}
