return {
  name = "rewriter",
  fields = {
    { config = {
        type = "record",
        nullable = false,
        fields = {
          { value = { type = "string" }, },
          { extra = { type = "string", default = "extra" }, },
        },
    }, },
  }
}
