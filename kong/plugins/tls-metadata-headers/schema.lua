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
  name = "tls-metadata-headers",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_https },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { inject_client_cert_details = {
            type = "boolean",
            description = "Enables TLS client certificate metadata values to be injected into HTTP headers.",
            default = false
          }, },
          { client_cert_header_name = {
            type = "string",
            required = true,
            description = "Define the HTTP header name used for the PEM format URL encoded client certificate.",
            default = "X-Client-Cert"
          }, },
          { client_serial_header_name = {
            type = "string",
            required = true,
            description = "Define the HTTP header name used for the serial number of the client certificate.",
            default = "X-Client-Cert-Serial"
          }, },
          { client_cert_issuer_dn_header_name = {
            type = "string",
            required = true,
            description = "Define the HTTP header name used for the issuer DN of the client certificate.",
            default = "X-Client-Cert-Issuer-DN"
          }, },
          { client_cert_subject_dn_header_name = {
            type = "string",
            required = true,
            description = "Define the HTTP header name used for the subject DN of the client certificate.",
            default = "X-Client-Cert-Subject-DN"
          }, },
          { client_cert_fingerprint_header_name = {
            type = "string",
            required = true,
            description = "Define the HTTP header name used for the SHA1 fingerprint of the client certificate.",
            default = "X-Client-Cert-Fingerprint"
          }, },
        },
    }, },
  },
}
