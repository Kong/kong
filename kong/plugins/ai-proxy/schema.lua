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
    {
      max_request_body_size = {
      type = "integer",
      default = 8 * 1024,
      gt = 0,
      description = "max allowed body size allowed to be introspected",}
    },
    { model_name_header = { description = "Display the model name selected in the X-Kong-LLM-Model response header",
    type = "boolean", default = true, }},
}

for i, v in pairs(ai_proxy_only_config) do
  this_schema.fields[#this_schema.fields+1] = v
end

return {
  name = "ai-proxy",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = this_schema },
  },
}
