-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  name = "collector",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { retry_count = { type = "number", default = 10 } },
          { queue_size = { type = "number", default = 100 } },
          { body_parsing_max_depth = { type = "number" } },
          { log_bodies = { type = "boolean", default = false } },
          { http_endpoint = { type = "string", required = true, default = "http://collector.com" } },
          { https_verify = { type = "boolean", default = false } },
        },
      },
    },
  },
}
