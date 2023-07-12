-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jq = require "resty.jq"

return {
  jq_program = {
    required = false,
    type = "string",
    custom_validator = function(jq_program)
      local jqp = jq.new()
      return jqp:compile(jq_program)
    end,
  },
  jq_options = {
    required = false,
    type = "record",
    default = {},
    fields = {
      {
        compact_output = {
          required = true,
          type = "boolean",
          default = true,
        },
      },
      {
        raw_output = {
          required = true,
          type = "boolean",
          default = false,
        },
      },
      {
        join_output = {
          required = true,
          type = "boolean",
          default = false,
        },
      },
      {
        ascii_output = {
          required = true,
          type = "boolean",
          default = false,
        },
      },
      {
        sort_keys = {
          required = true,
          type = "boolean",
          default = false,
        },
      },
    },
  },
  if_media_type = {
    required = false,
    type = "array",
    elements = {
      type = "string",
    },
    default = { "application/json" },
  },
  if_status_code = {
    required = false,
    type = "array",
    elements = {
      type = "integer",
      between = {
        100,
        599
      },
    },
    default = { 200 },
  },
}
