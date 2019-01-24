local typedefs = require "kong.db.schema.typedefs"


return {
  name = "short-circuit",
  fields = {
    {
      run_on = typedefs.run_on { default = "all" }
    },
    {
      config = {
        type = "record",
        fields = {
          { status  = { type = "integer", default = 503 }, },
          { message = { type = "string", default = "short-circuited" }, },
        },
      },
    },
  },
}
