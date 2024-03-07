-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local plugin_name = "xml-threat-protection"
local typedefs = require "kong.db.schema.typedefs"
local kb = 1024
local mb = kb * kb


local schema = {
  name = plugin_name,
  fields = {
    { protocols = typedefs.protocols_http },
    { consumer_group = typedefs.no_consumer_group },
    { config = {
        type = "record",
        fields = {
          { checked_content_types = { description = "A list of Content-Type values with payloads that must be validated.", type = "set",
            default = { "application/xml" },
            required = true,
            elements = {
              type = "string",
              required = true,
              match = "^[^%s]+%/[^ ;]+$",
            },
          }},
          { allowed_content_types = { description = "A list of Content-Type values with payloads that are allowed, but aren't validated.", type = "set",
            default = {},
            required = true,
            elements = {
              type = "string",
              required = true,
              match = "^[^%s]+%/[^ ;]+$",
            },
          }},
          { allow_dtd       = { description = "Indicates whether an XML Document Type Definition (DTD) section is allowed.", type = "boolean", required = true, default = false }},
          { namespace_aware = { description = "If not parsing namespace aware, all prefixes and namespace attributes will be counted as regular attributes and element names, and validated as such.", type = "boolean", required = true, default = true }},
          { max_depth       = { description = "Maximum depth of tags. Child elements such as Text or Comments are not counted as another level.", type = "integer", required = true, gt = 0, default = 50 }},
          { max_children    = { description = "Maximum number of children allowed (Element, Text, Comment, ProcessingInstruction, CDATASection). Note: Adjacent text and CDATA sections are counted as one. For example, text-cdata-text-cdata is one child.", type = "integer", required = true, gt = 0, default = 100 }},
          { max_attributes  = { description = "Maximum number of attributes allowed on a tag, including default ones. Note: If namespace-aware parsing is disabled, then the namespaces definitions are counted as attributes.", type = "integer", required = true, gt = 0, default = 100 }},
          { max_namespaces  = { description = "Maximum number of namespaces defined on a tag. This value is required if parsing is namespace-aware.", type = "integer", required = false,gt = 0, default = 20 }},
          { document        = { description = "Maximum size of the entire document.", type = "integer", required = true, gt = 0, default = 10 * mb }},
          { buffer          = { description = "Maximum size of the unparsed buffer (see below).", type = "integer", required = true, gt = 0, default = 1 * mb }},
          { comment         = { description = "Maximum size of comments.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { localname       = { description = "Maximum size of the localname. This applies to tags and attributes.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { prefix          = { description = "Maximum size of the prefix. This applies to tags and attributes. This value is required if parsing is namespace-aware.", type = "integer", required = false,gt = 0, default = 1 * kb }},
          { namespaceuri    = { description = "Maximum size of the namespace URI. This value is required if parsing is namespace-aware.", type = "integer", required = false,gt = 0, default = 1 * kb }},
          { attribute       = { description = "Maximum size of the attribute value.", type = "integer", required = true, gt = 0, default = 1 * mb }},
          { text            = { description = "Maximum text inside tags (counted over all adjacent text/CDATA elements combined).", type = "integer", required = true, gt = 0, default = 1 * mb }},
          { pitarget        = { description = "Maximum size of processing instruction targets.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { pidata          = { description = "Maximum size of processing instruction data.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entityname      = { description = "Maximum size of entity names in EntityDecl.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entity          = { description = "Maximum size of entity values in EntityDecl.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          { entityproperty  = { description = "Maximum size of systemId, publicId, or notationName in EntityDecl.", type = "integer", required = true, gt = 0, default = 1 * kb }},
          -- billion laughs mitigation
          { bla_max_amplification = { description = "Sets the maximum allowed amplification. This protects against the Billion Laughs Attack.", type = "number",  required = true, gt = 1 , default = 100 }},
          { bla_threshold         = { description = "Sets the threshold after which the protection starts. This protects against the Billion Laughs Attack.", type = "integer", required = true, gt = kb, default = 8 * mb }},
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
