return {
  name = "dummy",
  fields = {
    { config = {
        type = "record",
        fields = {
          { resp_header_value = { type = "string", default = "1" }, },
          { append_body = { type = "string" }, },
          { resp_code = { type = "number" }, },
    }, }, },
  },
}
