-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
--- Copyright 2019 Kong Inc.
local typedefs = require("kong.db.schema.typedefs")
local Schema = require "kong.db.schema"

typedefs.protocols_https = Schema.define {
  type = "set",
  required = true,
  default = { "https", "grpcs" },
  elements = { type = "string", one_of = { "https" , "grpcs", "tls" } },
}

return {
  name = "tls-handshake-modifier",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_https },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { tls_client_certificate = {
            required = false,
            type = "string",
            description = "TLS Client Certificate",
            one_of = {"REQUEST"},
            default = "REQUEST"
          }, },
        },
    }, },
  },
}
