return {
  name = "rewriter",
  fields = {
    { config = {
        type = "record",
        fields = {
          { value = { type = "string" }, },
          { extra = { type = "string", default = "extra" }, },
        },
    }, },
  }
}
