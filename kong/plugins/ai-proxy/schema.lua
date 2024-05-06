local typedefs = require("kong.db.schema.typedefs")
local llm = require("kong.llm")
local deep_copy = require("kong.tools.table").deep_copy

local this_schema = deep_copy(llm.config_schema)

local ai_proxy_only_config = {
    {
      response_streaming = {
        type = "string",
        description = "Whether to 'optionally allow', 'deny', or 'always' (force) the streaming of answers via server sent events.",
        required = false,
        default = "allow",
        one_of = { "allow", "deny", "always" }},
    },
}

for i, v in pairs(ai_proxy_only_config) do
  this_schema.fields[#this_schema.fields+1] = v
end

return {
  name = "ai-proxy",
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer = typedefs.no_consumer },
    { service = typedefs.no_service },
    { config = this_schema },
  },
}
