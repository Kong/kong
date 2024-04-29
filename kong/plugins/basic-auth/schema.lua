-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"


return {
  name = "basic-auth",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http_and_ws },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { anonymous = { description = "An optional string (Consumer UUID or username) value to use as an “anonymous” consumer if authentication fails. If empty (default null), the request will fail with an authentication failure `4xx`. Please note that this value must refer to the Consumer `id` or `username` attribute, and **not** its `custom_id`.", type = "string" }, },
          { hide_credentials = { description = "An optional boolean value telling the plugin to show or hide the credential from the upstream service. If `true`, the plugin will strip the credential from the request (i.e. the `Authorization` header) before proxying it.", type = "boolean", required = true, default = false }, },
          { realm = { description = "When authentication fails the plugin sends `WWW-Authenticate` header with `realm` attribute value.", type = "string", required = true, default = "service" }, },
    }, }, },
  },
}
