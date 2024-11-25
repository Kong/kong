-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"
local ngx_null = ngx.null

local regex_threat = {
  type = "record",
  fields = {
    { name = { type = "string", required = true,
      description = "A unique name for this injection." }, },
    { regex = { type = "string", required = true, is_regex = true, 
      description = "The regex to match against." }, },
  },
}


local schema = {
  name = "injection-protection",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {

          { injection_types = { type = "set", required = true, default = {"sql"},
            elements = { type = "string", one_of = { "sql", "js", "ssi", "xpath_abbreviated", "xpath_extended", "java_exception", } },
            description = "The type of injections to check for." }, },
          { locations = { type = "set", required = true, default = {"path_and_query"},
            elements = { type = "string", one_of = { "headers", "path_and_query", "body" } },
            description = "The locations to check for injection." }, },
          { custom_injections = { type = "array", elements = regex_threat, default = ngx_null,
            description = "Custom regexes to check for." }, },
          { enforcement_mode = { type = "string", required = true, one_of = { "block", "log_only" }, default = "block",
            description = "Enforcement mode of the security policy." }, },
          { error_status_code = { type = "integer", required = true, default = 400, between = {400, 499},
            description = "The response status code when validation fails." }, },
          { error_message = { type = "string", required = true, default = "Bad Request",
            description = "The response message when validation fails" }, },
        },
        entity_checks = {
          { at_least_one_of = { "injection_types", "custom_injections" } },
        },
      },
    },
  },

}

return schema