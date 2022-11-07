-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)") -- Grab pluginname from module name
local typedefs = require "kong.db.schema.typedefs"
local kb = 1024
local mb = kb * kb


local schema = {
  name = plugin_name,
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { checked_content_types = {
            type = "set",
            default = { "application/xml" },
            required = true,
            elements = {
              type = "string",
              required = true,
              match = "^[^%s]+%/[^ ;]+$",
            },
          }},
          { allowed_content_types = {
            type = "set",
            default = {},
            required = true,
            elements = {
              type = "string",
              required = true,
              match = "^[^%s]+%/[^ ;]+$",
            },
          }},
          { allow_dtd       = { type = "boolean", required = true, default = false }},
          { namespace_aware = { type = "boolean", required = true, default = true }},
          { max_depth       = { type = "integer", required = true, gt = 0, default = 50 }},
          { max_children    = { type = "integer", required = true, gt = 0, default = 100 }},
          { max_attributes  = { type = "integer", required = true, gt = 0, default = 100 }},
          { max_namespaces  = { type = "integer", required = false,gt = 0, default = 20 }},
          { document        = { type = "integer", required = true, gt = 0, default = 10 * mb }},
          { buffer          = { type = "integer", required = true, gt = 0, default = 1 * mb }},
          { comment         = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { localname       = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { prefix          = { type = "integer", required = false,gt = 0, default = 1 * kb }},
          { namespaceuri    = { type = "integer", required = false,gt = 0, default = 1 * kb }},
          { attribute       = { type = "integer", required = true, gt = 0, default = 1 * mb }},
          { text            = { type = "integer", required = true, gt = 0, default = 1 * mb }},
          { pitarget        = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { pidata          = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entityname      = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entity          = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entityproperty  = { type = "integer", required = true, gt = 0, default = 1 * kb }},
          -- billion laughs mitigation
          { bla_max_amplification = { type = "number",  required = true, gt = 1 , default = 100 }},
          { bla_threshold         = { type = "integer", required = true, gt = kb, default = 8 * mb }},
        },
        entity_checks = {
          { conditional = { if_field = "namespace_aware",
            if_match = { eq = true },
            then_field = "max_namespaces",
            then_match = { required = true }}},
          { conditional = { if_field = "namespace_aware",
            if_match = { eq = true },
            then_field = "prefix",
            then_match = { required = true }}},
          { conditional = { if_field = "namespace_aware",
            if_match = { eq = true },
            then_field = "namespaceuri",
            then_match = { required = true }}},
        },
      },
    },
  },
}

return schema
