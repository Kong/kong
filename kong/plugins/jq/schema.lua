local typedefs = require "kong.plugins.jq.typedefs"

return {
  name = "jq",
  fields = {
    typedefs.protocols,
    {
      config = {
        type = "record",
        fields = {
          {
            filters = {
              required = true,
              type = "array",
              elements = {
                required = true,
                type = "record",
                fields = {
                  typedefs.context,
                  typedefs.target,
                  typedefs.program,
                  typedefs.jq_options,
                  typedefs.if_media_type,
                  typedefs.if_status_code,
                },
              },
            },
          },
        },
      },
    },
  },
}
