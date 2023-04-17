-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "datadog-tracing",
  fields = {
    { consumer = typedefs.no_consumer },
    -- TODO: support stream mode
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        -- Agent endpoint by default
        { endpoint = typedefs.url { referenceable = true } },
        { service_name = { type = "string", required = true, default = "kong" } },
        { environment = { type = "string", default = "none" } },
        { batch_span_count = { type = "integer", required = true, default = 200 } },
        { batch_flush_delay = { type = "integer", required = true, default = 3 } },
        { connect_timeout = typedefs.timeout { default = 1000 } },
        { send_timeout = typedefs.timeout { default = 5000 } },
        { read_timeout = typedefs.timeout { default = 5000 } },
        -- TODO: sampling_rate controlled by the plugin, for now it's controlled by the `opentelemetry_tracing_sampling_rate`
        { queue = typedefs.queue },
      },
    }, },
  },
}
