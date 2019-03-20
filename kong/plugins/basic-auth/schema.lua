local typedefs = require "kong.db.schema.typedefs"


return {
  name = "basic-auth",
  fields = {
    { kongsumer = typedefs.no_kongsumer },
    { run_on = typedefs.run_on_first },
    { config = {
        type = "record",
        fields = {
          { anonymous = { type = "string", uuid = true, legacy = true }, },
          { hide_credentials = { type = "boolean", default = false }, },
    }, }, },
  },
}
