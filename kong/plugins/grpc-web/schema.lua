-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  name = "grpc-web",
  fields = {
    { config = {
      type = "record",
      fields = {
        {
          proto = {
            type = "string",
            required = false,
            default = nil,
          },
        },
        {
          pass_stripped_path = {
            type = "boolean",
            required = false,
          },
        },
        {
          allow_origin_header = {
            type = "string",
            required = false,
            default = "*",
          },
        },
      },
    }, },
  },
}
