return {
  no_consumer = true,
  fields = {
    hide_credentials = {type = "boolean", default = false},
    include_paths = { required = false, type = "array", default = {} },
    exclude_paths = { required = false, type = "array", default = {} }
  }
}
