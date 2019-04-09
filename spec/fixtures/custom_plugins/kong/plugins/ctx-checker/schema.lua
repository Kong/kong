return {
  fields = {
    ctx_set_field   = { type = "string" },
    ctx_set_value   = { type = "string", default = "set_by_ctx_checker" },
    ctx_check_field = { type = "string" },
    ctx_check_value = { type = "string" },
    ctx_kind        = { type = "string", default = "ngx.ctx" },
    ctx_throw_error = { type = "boolean", default = false },
  }
}
