-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  name = "reference-ca-cert",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { pre_key = { type = "string", }, },
          { ca_certificates = { type = "array", required = true, elements = { type = "string", uuid = true, }, }, },
          { post_key = { type = "string", }, },
        },
      },
    },
  },
}
