local typedefs = require "kong.plugins.jq-request-filter.typedefs"


return {
  name = "jq-request-filter",
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
                  typedefs.program,
                  typedefs.target,
                  typedefs.opts,
                  typedefs.mime,
                },
              },
            },
          },
        },
      },
    },
  },
}
