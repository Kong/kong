local typedefs = require("kong.db.schema.typedefs")
local llm = require("kong.llm")

return {
  name = "ai-proxy",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { config = llm.config_schema },
  },
}
