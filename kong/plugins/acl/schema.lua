-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "acl",
  fields = {
    { consumer = typedefs.no_consumer },
    { consumer_group = typedefs.no_consumer_group },
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { allow = { description = "Arbitrary group names that are allowed to consume the service or route. One of `config.allow` or `config.deny` must be specified.",
              type = "array",
              elements = { type = "string" }, }, },
          { deny = { description = "Arbitrary group names that are not allowed to consume the service or route. One of `config.allow` or `config.deny` must be specified.",
              type = "array",
              elements = { type = "string" }, }, },
          { hide_groups_header = { type = "boolean", required = true, default = false, description = "If enabled (`true`), prevents the `X-Consumer-Groups` header from being sent in the request to the upstream service." }, },
          { include_consumer_groups = { type = "boolean", required = false, default = false, description = "If enabled (`true`), allows the consumer-groups to be used in the `allow|deny` fields" }, },
          { always_use_authenticated_groups = { type = "boolean", required = true, default = false, description = "If enabled (`true`), the authenticated groups will always be used even when an authenticated consumer already exists. If the authenticated groups don't exist, it will fallback to use the groups associated with the consumer. By default the authenticated groups will only be used when there is no consumer or the consumer is anonymous." } },
        },
      }
    }
  },
  entity_checks = {
    { only_one_of = { "config.allow", "config.deny" }, },
    { at_least_one_of = { "config.allow", "config.deny" }, },
  },
}
