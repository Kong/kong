return {
  fields = {
    certificate   = { type = "boolean", required = false, default = false },
    rewrite       = { type = "boolean", required = false, default = false },
    preread       = { type = "boolean", required = false, default = false },
    access        = { type = "boolean", required = false, default = false },
    header_filter = { type = "boolean", required = false, default = false },
    body_filter   = { type = "boolean", required = false, default = false },
    log           = { type = "boolean", required = false, default = false },
  }
}
