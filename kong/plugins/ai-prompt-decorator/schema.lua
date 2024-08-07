local typedefs = require "kong.db.schema.typedefs"

local prompt_record = {
  type = "record",
  required = false,
  fields = {
    { role = { type = "string", required = true, one_of = { "system", "assistant", "user" }, default = "system" }},
    { content = { type = "string", required = true, len_min = 1, len_max = 500 } },
  }
}

local prompts_record = {
  type = "record",
  required = false,
  fields = {
    { prepend = {
      type = "array",
      description = "Insert chat messages at the beginning of the chat message array. "
                 .. "This array preserves exact order when adding messages.",
      elements = prompt_record,
      required = false,
      len_max = 15,
    }},
    { append = {
      type = "array",
      description = "Insert chat messages at the end of the chat message array. "
                 .. "This array preserves exact order when adding messages.",
      elements = prompt_record,
      required = false,
      len_max = 15,
    }},
  }
}

return {
  name = "ai-prompt-decorator",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { prompts = prompts_record },
          { max_request_body_size = { type = "integer", default = 8 * 1024, gt = 0,
                                    description = "max allowed body size allowed to be introspected" } },
        }
      }
    }
  },
  entity_checks = {
    { at_least_one_of = { "config.prompts.prepend", "config.prompts.append" } },
  },
}
