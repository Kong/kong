local typedefs = require "kong.db.schema.typedefs"

return {
  protocols = {
    protocols = typedefs.protocols_http
  },
  context = {
    context = {
      type = "string",
      default = "response",
      one_of = {
        "request",
        "response",
      },
    },
  },
  program = {
    program = {
      required = true,
      type = "string",
    },
  },
  target = {
    target = {
      type = "string",
      default = "body",
      one_of = {
        "body",
        "headers",
      },
    },
  },
  jq_options = {
    jq_options = {
      required = false,
      type = "record",
      default = {},
      fields = {
        {
          compact_output = {
            type = "boolean",
            default = true,
          },
        },
        {
          raw_output = {
            type = "boolean",
            default = false,
          },
        },
        {
          join_output = {
            type = "boolean",
            default = false,
          },
        },
        {
          ascii_output = {
            type = "boolean",
            default = false,
          },
        },
        {
          sort_keys = {
            type = "boolean",
            default = false,
          },
        },
      },
    },
  },
  if_media_type = {
    if_media_type = {
      required = false,
      type = "array",
      elements = {
        type = "string",
      },
      default = { "application/json" },
    },
  },
  if_status_code = {
    if_status_code = {
      required = false,
      type = "array",
      elements = {
        type = "integer",
        between = {
          100,
          599
        },
      },
      default = { 200 },
    },
  },
}

