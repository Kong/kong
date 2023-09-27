-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local typedefs = require "kong.db.schema.typedefs"


return {
  name = "aws",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          {
            region = {
              type = "string",
              one_of = {
                "us-east-2",
                "us-east-1",
                "us-west-1",
                "us-west-2",
                "af-south-1",
                "ap-east-1",
                "ap-southeast-3",
                "ap-south-1",
                "ap-northeast-3",
                "ap-northeast-2",
                "ap-southeast-1",
                "ap-southeast-2",
                "ap-northeast-1",
                "ca-central-1",
                "eu-central-1",
                "eu-west-1",
                "eu-west-2",
                "eu-south-1",
                "eu-west-3",
                "eu-north-1",
                "me-south-1",
                "sa-east-1",
                "us-gov-east-1",
                "us-gov-west-1",
              },
            },
          },
          { endpoint_url = typedefs.url },
          { assume_role_arn = { type = "string" } },
          { role_session_name = { type = "string", default = "KongVault", required = true } },
          { ttl           = typedefs.ttl },
          { neg_ttl       = typedefs.ttl },
          { resurrect_ttl = typedefs.ttl },
        },
      },
    },
  },
}
