local typedefs = require "kong.db.schema.typedefs"

-- local prompt_schema = {
--   type = "record",
--   required = false,
--   fields = {
--     { role = { type = "string", required = false, one_of = { "system", "assistant", "user" }, default = "system" }},
--     { content = { type = "string", required = true } },
--     { position = { type = "string", required = true, one_of = { "BEGINNING", "AFTER_FINAL_SYSTEM", "AFTER_FINAL_ASSISTANT" "END" }, default = "BEGINNING" }},
--   }
-- }

local prompt_record = {
  type = "record",
  required = false,
  fields = {
    { role = { type = "string", required = true, one_of = { "system", "assistant", "user" }, default = "system" }},
    { content = { type = "string", required = true } },
  }
}

local prompts_record = {
  type = "record",
  required = false,
  fields = {
    { prepend = {
      type = "array",
      description = [[Insert chat messages at the beginning of the chat message array.
                      This array preserves exact order when adding messages.]],
      elements = prompt_record,
      required = false,
    }},
    { append = {
      type = "array",
      description = [[Insert chat messages at the end of the chat message array.
                      This array preserves exact order when adding messages.]],
      elements = prompt_record,
      required = false,
    }},
  }
}

return {
  name = "ai-prompt-injector",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
          { prompts = prompts_record }
        }
      }
    }
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = { "config" },
        fn = function(entity)
          local config = entity.config
  
          if config and config.prompts ~= ngx.null then
            local head_prompts_set = (config.prompts.prepend ~= ngx.null) and (#config.prompts.prepend > 0)
            local tail_prompts_set = (config.prompts.append ~= ngx.null) and (#config.prompts.append > 0)

            if (not head_prompts_set) and (not tail_prompts_set) then
              return nil, "must set one array item in either [prompts.prepend] or [prompts.append]"
            end

          else
            return nil, "must specify one or more [prompts.prepend] or [prompts.append] to add to requests"

          end

          return true
        end
      }
    }
  }
}
