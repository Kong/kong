--- A library of ready-to-use type synonyms to use in schema definitions.
-- @module kong.db.schema.typedefs

local typedefs = {}
local Schema = require("kong.db.schema")

typedefs.http_method = Schema.define {
  type = "string",
  match = "^%u+$",
}

typedefs.port = Schema.define {
  type = "integer",
  between = { 0, 65535 }
}

typedefs.protocol = Schema.define {
  type = "string",
  one_of = {
    "http",
    "https"
  }
}

typedefs.timeout = Schema.define {
  type = "integer",
  between = { 0, math.pow(2, 31) - 2 },
}

typedefs.uuid = Schema.define {
  type = "string",
  uuid = true,
  auto = true,
}

return typedefs
