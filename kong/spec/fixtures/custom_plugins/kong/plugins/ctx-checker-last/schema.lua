return {
  name = "ctx-checker-last",
  fields = {
    {
      config = {
        type = "record",
        fields = {
          { ctx_set_field   = { type = "string" } },
          { ctx_set_value   = { type = "string", default = "set_by_ctx_checker" } },
          { ctx_set_array   = { type = "array", elements = { type = "string" } } },
          { ctx_check_field = { type = "string" } },
          { ctx_check_value = { type = "string" } },
          { ctx_check_array = { type = "array", elements = { type = "string" } } },
          { ctx_kind        = { type = "string", default = "ngx.ctx" } },
          { ctx_throw_error = { type = "boolean", default = false } },
        },
      },
    },
  },
}
