local typedefs = require "kong.db.schema.typedefs"


return {
  protocols = {
    protocols = typedefs.protocols_http
  },
  program = {
    program = {
      required = true,
      type = "string",
    },
  },
  target = {
    target = {
      required = true,
      type = "string",
      default = "body",
      one_of = {
        "body",
        "headers",
      },
    },
  },
  mime = {
    mime = {
      required = true,
      type = "record",
      default = {},
      fields = {
        {
          ["in"] = {
            type = "string",
          },
        },
        {
          out = {
            type = "string",
          },
        },
      },
    },
  },
  status = {
    status = {
      required = true,
      type = "record",
      default = {},
      fields = {
        {
          ["in"] = {
            type = "integer",
            between = {
              100,
              599,
            },
          },
        },
        {
          out = {
            type = "integer",
            between = {
              100,
              599,
            },
          }
        },
      },
    },
  },
  opts = {
    opts = {
      required = false,
      type = "record",
      default = {},
      fields = {
        {
          raw = {
            required = true,
            type = "boolean",
            default = false,
          },
        },
        {
          join = {
            required = true,
            type = "boolean",
            default = false,
          },
        },
        {
          flags = {
            required = true,
            type = "integer",
            default = 0,
          },
        },
        {
          dump = {
            required = true,
            type = "integer",
            default = 0,
          },
        },
      },
    },
  },
}

