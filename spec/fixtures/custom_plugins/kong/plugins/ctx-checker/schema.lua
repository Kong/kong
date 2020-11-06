-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  fields = {
    ctx_set_field   = { type = "string" },
    ctx_set_value   = { type = "string", default = "set_by_ctx_checker" },
    ctx_set_array   = { type = "array"  },
    ctx_check_field = { type = "string" },
    ctx_check_value = { type = "string" },
    ctx_check_array = { type = "array"  },
    ctx_kind        = { type = "string", default = "ngx.ctx" },
    ctx_throw_error = { type = "boolean", default = false },
  }
}
